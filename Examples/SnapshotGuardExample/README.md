# SnapshotGuardExample

A small app with one card, and three snapshot tests of it: the card in light and in dark, and a piece of text. It is here so that you can see a reference being recorded, a comparison failing, and `snapshot-guard fetch` and `snapshot-guard check` at work, before putting `SnapshotGuard` into your own test target.

The references are not in the repository. An image only compares equal in the environment that recorded it, so the example records its own on your machine, and that is the first thing to watch.

## Run it

Everything runs in a simulator, and nothing needs signing. From this directory:

```sh
run_tests() {
  xcodebuild test -project SnapshotGuardExample.xcodeproj -scheme SnapshotGuardExample \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' "$@"
}
```

Use the name of a simulator you have. You can also open `SnapshotGuardExample.xcodeproj` and press ⌘U.

### 1. Record

```sh
run_tests
```

The three tests **fail**. Each has written its reference to `SnapshotGuardExampleTests/__Snapshots__/ProfileCardSnapshotTests`, and says so:

```
No reference for “light.1.png” exists. This run recorded one at …/light.1.png.
Review it and commit it; the test passes once the reference exists before the run starts.
```

A run that records is never a run that passes. Look at the images, then:

```sh
run_tests
```

Now the tests pass.

### 2. Change the card

The card is drawn in another colour and with a little more room when `EXAMPLE_CHANGED=1` is in the environment. That stands in for a change nobody meant to make. `xcodebuild` passes on variables that start with `TEST_RUNNER_`:

```sh
TEST_RUNNER_EXAMPLE_CHANGED=1 run_tests -resultBundlePath changed.xcresult
```

The two image tests fail, and say how much differs:

```
“light.1.png” does not match its reference. 74358 of 1053000 pixels differ (7.062%, allowed 0.000%).
The largest difference in a colour channel is 255 of 255.
```

Open `changed.xcresult` in Xcode. Each failed test carries the snapshot of this run, the reference, and an image of the pixels that differ. The text test still passes, because the text did not change.

### 3. Bring a reference back the way CI does

On CI nothing is recorded. A snapshot without a reference is attached to its test instead, and `snapshot-guard fetch` puts it in place. Delete a reference and run the tests that way:

```sh
rm SnapshotGuardExampleTests/__Snapshots__/ProfileCardSnapshotTests/dark.1.png
TEST_RUNNER_SNAPSHOT_GUARD_RECORD=never run_tests -resultBundlePath missing.xcresult
```

`dark()` fails and nothing is written. Then, from the root of this repository:

```sh
swift run snapshot-guard fetch \
  --xcresult Examples/SnapshotGuardExample/missing.xcresult \
  --snapshots-dir Examples/SnapshotGuardExample/SnapshotGuardExampleTests/__Snapshots__
```

The reference is back, and the tests pass again. With `--include-mismatched` and `changed.xcresult`, the same command adopts the changed card as the new reference.

### 4. Check the references

```sh
swift run snapshot-guard check \
  --snapshots-dir Examples/SnapshotGuardExample/SnapshotGuardExampleTests/__Snapshots__ --strict
```

It reports references that are identical, flat, or recorded in more than one environment. Here it finds nothing.

## Where the calls are

- `SnapshotGuardExampleTests/ProfileCardSnapshotTests.swift` holds the suite, with the `.snapshots` trait and the calls to `expectSnapshot`.
- `SnapshotGuardExample/ProfileCard.swift` is the view.
- `project.yml` makes the application the host of the test target. Images of views are drawn through a window, and that needs one.

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen). After changing `project.yml`, run `xcodegen generate` in this directory.
