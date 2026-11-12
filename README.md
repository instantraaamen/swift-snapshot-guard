# swift-snapshot-guard

Keep [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) honest when the references are recorded on CI.

[日本語](README.ja.md)

Snapshot references only match the environment that recorded them. Text can rasterize differently on a CI machine and on your Mac even with the same simulator build, so many teams treat the images CI draws as the source of truth. That workflow has three sharp edges, and this package files them down:

| Problem | What you get |
|---|---|
| A missing reference is recorded and the test fails, but a retry compares against the file that was just written and **passes**. CI goes green with nothing compared. | `assertGuardedSnapshot` fails the retry too. |
| The recorded images are buried in an `.xcresult` bundle under names like `test.Name_0_<UUID>.png`. | `snapshot-guard fetch` puts them back under their reference names. |
| A screen that failed to draw produces a blank image that is happily committed as the reference. | `snapshot-guard check` reports images with identical bytes. |

## Installation

Add the package to your test target:

```swift
.package(url: "https://github.com/instantraaamen/swift-snapshot-guard", from: "0.1.0")
```

```swift
.testTarget(
  name: "AppTests",
  dependencies: [.product(name: "SnapshotGuard", package: "swift-snapshot-guard")]
)
```

## The guard

`assertGuardedSnapshot` takes the same arguments as `assertSnapshot`:

```swift
import SnapshotGuard
import SnapshotTesting
import Testing

@MainActor
@Test func profile() {
  assertGuardedSnapshot(of: ProfileView(), as: .keyWindowImage(layout: .device(config: .iPhone13)))
}
```

When a reference is missing, swift-snapshot-testing records it and fails. If the same test runs again in the same process, the guard remembers that the reference was only recorded and fails again, with a message that says so.

The guard reads the wording of the library's failure message. Add one test so that an upgrade that changes the wording is noticed:

```swift
@Test func snapshotGuardIsAlive() {
  #expect(SnapshotGuard.missingReferenceCheck() == nil)
}
```

Things to know:

- Failures are reported to Swift Testing. From XCTest, call `verifyGuardedSnapshot` and pass the result to `XCTFail`.
- The guard lives in memory, so it covers retries in the same process, such as the "Retry on Failure" setting of a test plan. It cannot see a retry that relaunches the test runner.
- Snapshots without a name share one entry per test function.

### `.keyWindowImage`

A strategy for SwiftUI views that renders through the host application's key window and compares without perceptual matching.

- The default off-screen path draws nothing for `glassEffect` on recent iOS versions, so a screen built from glass comes out blank. Drawing through the key window fixes that. Your test target needs a host application.
- `perceptualPrecision` below `1` makes the library compare without colour management. Two images that look identical can then be reported as far apart when one came from a wide-gamut window and the other from an sRGB PNG. This strategy pins it to `1`; use `precision` for tolerance.

## Running only where the references are valid

```swift
let snapshots = SnapshotEnvironment(baselineOSVersion: "18.2", policy: .ciOnly)

@Suite(.enabled(if: snapshots.shouldRun, snapshots.skipReason))
struct ScreenSnapshotTests { ... }
```

`.baselineOSOnly` runs on the given OS version on any machine. `.ciOnly` additionally requires that the repository checkout is not visible, which is the case on CI services that build on one machine and test on another, such as Xcode Cloud.

On those services the path derived from `#filePath` does not exist either. Copy `__Snapshots__` into the test bundle as resources and let `SnapshotDirectory` choose:

```swift
let directory = SnapshotDirectory.resolve(suite: "ScreenSnapshotTests", fallback: Bundle(for: Token.self))
assertGuardedSnapshot(of: view, as: .keyWindowImage(), snapshotDirectory: directory)
```

`withCleanUserDefaults(domain:)` clears the host application's defaults for the duration of a test and restores them afterwards.

## The command line tool

```sh
swift run snapshot-guard fetch --xcresult Test.xcresult --snapshots-dir Tests/AppTests/__Snapshots__
```

To re-record references:

1. Delete the reference images you want to replace.
2. Run the tests on CI. They fail, and the recorded images are attached to the result bundle.
3. Run `snapshot-guard fetch`.
4. Look at every image, then commit.

`fetch` skips the `failure` / `reference` / `difference` images of an ordinary mismatch and anything a retry produced. It expects the default layout of swift-snapshot-testing with one suite per file, where the suite type is named after the file. Requires Xcode 16 or later.

### Xcode Cloud

`fetch` can download the result bundle itself:

```sh
export APP_STORE_CONNECT_API_KEY_KEY_ID=...
export APP_STORE_CONNECT_API_KEY_ISSUER_ID=...
export APP_STORE_CONNECT_API_KEY_KEY_FILEPATH=~/keys/AuthKey.p8

swift run snapshot-guard fetch --xcode-cloud --workflow "Tests" \
  --snapshots-dir Tests/AppTests/__Snapshots__
```

It picks the latest finished build, or the one given with `--build`. The environment variables are the ones fastlane uses.

### Checking references

```sh
swift run snapshot-guard check --snapshots-dir Tests/AppTests/__Snapshots__ --strict
```

Reports images with identical bytes, and images in different suites that share a file name. The second matters when references are flattened into a test bundle.

## License

MIT. See [LICENSE](LICENSE).
