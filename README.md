# swift-snapshot-guard

Snapshot tests for Swift Testing that cannot pass by accident.

[日本語](README.ja.md)

A snapshot test compares what a view looks like now with an image that was recorded earlier. It is only worth something while that comparison actually happens, and there are several quiet ways for it to stop happening:

- A test that has no reference records one and fails, the test plan retries it, and the retry passes against the file the first attempt just wrote.
- A view draws nothing, the blank image becomes the reference, and blank matches blank on every run after that.
- A reference is deleted to be recorded again and then forgotten, and nobody notices because the suite is skipped everywhere except on CI.
- Two renderings of the same screen are compared in different colour spaces, and the test fails for a difference no one can see.

Each of these happened in the app this package was written for, some of them more than once. `swift-snapshot-guard` is a snapshot testing library built so that they cannot, and a command line tool for the part of the work that happens around CI.

It has no dependencies beyond [swift-argument-parser](https://github.com/apple/swift-argument-parser), which only the command line tool uses.

## Installation

```swift
.package(url: "https://github.com/instantraaamen/swift-snapshot-guard", from: "0.1.0")
```

Add the `SnapshotGuard` product to your test target. It needs Swift 6.2, and iOS 17, tvOS 17, visionOS 1 or macOS 14.

Images of views are drawn through a real window, so the test target needs a host application. Strategies for `CGImage`, text and data work without one.

## Usage

```swift
import SnapshotGuard
import Testing

@MainActor
@Suite(.snapshots(recording: .never))
struct ProfileSnapshotTests {
  @Test func profile() async {
    await expectSnapshot(
      of: ProfileView(user: .sample),
      as: .image(layout: .fixed(width: 390, height: 844), traits: { $0.userInterfaceStyle = .dark })
    )
  }
}
```

The reference lives next to the test, in `__Snapshots__/ProfileSnapshotTests/profile.1.png`. Pass `named:` to give a snapshot a name instead of a number.

`expectSnapshot` records an issue and lets the test go on, so one run reports every screen that changed. `requireSnapshot` throws instead.

### When there is no reference

The test fails. What else happens is up to `recording`:

| | |
|---|---|
| `.never` | Nothing is written. The snapshot is attached to the test. Use this on CI. |
| `.missing` | The reference is written, and the test passes from the next run on. The default. |
| `.all` | Every reference is written again, and every test fails, so that a recording run is never mistaken for a verification. |

With `.missing`, a reference that this process wrote is never accepted by the same process. A retried test fails again, with a message that says nothing was verified.

`SNAPSHOT_GUARD_RECORD=never` (or `missing`, `all`) sets the default from the environment.

### When the snapshot differs

The failure says how much differs, and attaches the snapshot, the reference and an image of the differing pixels:

```
“Profile” does not match its reference. 1284 of 1318320 pixels differ (0.097%, allowed 0.000%).
The largest difference in a colour channel is 37 of 255.
```

A reference carries the environment it was recorded in. When that is not the environment of the test run, the message says so, because another system version draws text differently and no change to the app is involved:

```
The reference was recorded in another environment (this run: iOS 18.2 instead of iOS 18.1).
```

### Tolerance

Images are compared pixel by pixel, after both have been brought into 8-bit sRGB. By default every pixel has to match.

```swift
@Suite(.snapshots(imageTolerance: .pixels(0.002)))            // for a whole suite
.image(tolerance: .pixels(0.01))                               // for one snapshot
.image(tolerance: .exact.ignoring(CGRect(x: 170, y: 400, width: 50, height: 50)))
```

- `differingPixelShare` is the share of pixels that may differ.
- `channelDelta` is how far a colour channel may be off before a pixel counts as differing. `1` absorbs rounding.
- `ignoredRegions` leaves areas out, in points. Prefer this for a spinner or a clock over a tolerance that covers the whole screen.

The tolerance of a suite applies wherever a snapshot does not set its own.

### Blank images

An image of one flat colour is rejected before it is compared or recorded, because that is what a view that failed to draw looks like. Pass `allowsUniformImage: true` when a flat image is what the test is about.

### Waiting for a view

By default the snapshot is taken as soon as the view has been laid out. `settling` waits for more:

```swift
.image(settling: .mainQueueDrained)                 // work already queued on the main queue has run
.image(settling: .until { store.isLoaded })         // a condition holds
.image(settling: .delay(.milliseconds(300)))
```

`.mainQueueDrained` is the one to reach for when state arrives through `DispatchQueue.main.async` or `receive(on: DispatchQueue.main)`. Spinning a run loop from the test does not deliver it.

### How views are drawn

A view is put into a window of its own, in the host application's scene, and drawn the way the screen shows it. Materials and effects that only the compositor produces, such as glass, come out as they look on a device; an off-screen rendering of the layer leaves them out.

The window has the size the snapshot asks for and no safe area unless you pass one, so the same view renders the same way on every simulator. The host application's own window is not touched.

## Suites that only compare on CI

Images only compare equal in the environment that recorded them. Even the same simulator build can rasterize text differently on a CI machine and on a developer machine. The usual answer is to skip image suites everywhere except on CI, and a skipped suite cannot notice that a reference has gone missing.

Run the suite everywhere instead, and let it check only what it can:

```swift
let environment = SnapshotEnvironment(baselineOSVersion: "18.2", policy: .ciOnly)

@MainActor
@Suite(.snapshots(recording: .never, verifying: environment.shouldRun ? .comparison : .referenceExists))
struct ScreenSnapshotTests { ... }
```

With `.referenceExists`, nothing is rendered. The test fails when its reference does not exist, on every machine, at the moment the reference was deleted.

On a CI service that builds on one machine and tests on another, such as Xcode Cloud, the test machine has no checkout. The references are then read from the test bundle: copy `__Snapshots__` into the test target as resources.

## Bringing references back from CI

A failing snapshot is attached to its test under a name that says what it is and where it belongs. The command line tool reads those attachments from a result bundle and puts them in place:

```sh
swift run snapshot-guard fetch --xcresult Test.xcresult --snapshots-dir Tests/__Snapshots__
```

- By default it takes the snapshots that had no reference.
- `--include-mismatched` also takes the snapshots that did not match. After an intended change, that adopts what the screens look like now, without deleting references first.
- `--dry-run` lists what would be written, and `--verbose` lists what is left out and why.
- `--xcode-cloud` downloads the result bundle of an Xcode Cloud build, with `--workflow` and `--build` to choose it. It needs an App Store Connect API key in `APP_STORE_CONNECT_API_KEY_KEY_ID`, `APP_STORE_CONNECT_API_KEY_ISSUER_ID` and `APP_STORE_CONNECT_API_KEY_KEY_FILEPATH`, the names fastlane uses.

Look at every image before you commit it.

## Checking the references

```sh
swift run snapshot-guard check --snapshots-dir Tests/__Snapshots__ --strict
```

reports

- references with identical bytes, and references of one flat colour, which usually mean nothing was drawn;
- references in different directories that share a file name, which overwrite each other when they are flattened into a test bundle;
- references that were recorded in more than one environment, which cannot all match one test run.

## Other formats

```swift
await expectSnapshot(of: formatter.string(from: date), as: .text)
await expectSnapshot(of: archive, as: .data)
await expectSnapshot(of: cgImage, as: .image())
```

A strategy says how a value becomes bytes and how two sets of bytes are compared. Make your own with `SnapshotStrategy(pathExtension:validate:compare:encode:)`, or derive one from an existing strategy with `pullback`.

## How this compares

[swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) is the established library, with far more strategies, XCTest support and inline snapshots. Reach for it when you need those.

This package covers less and is stricter about it. It is built on Swift Testing only, draws views through a window by default, never lets a recording count as a pass, and treats getting references back from CI as part of the job.

## Products

| Product | For | Contains |
|---|---|---|
| `SnapshotGuard` | test targets | `expectSnapshot`, the strategies and the `.snapshots` trait. |
| `SnapshotGuardTools` | your own tooling | Reading result bundles, placing references and auditing them. |
| `snapshot-guard` | the command line | `fetch` and `check`. |

## License

Apache License 2.0. See [LICENSE.txt](LICENSE.txt).
