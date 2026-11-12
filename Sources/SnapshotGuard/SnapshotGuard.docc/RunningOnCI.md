# Running snapshot tests on CI

Keep image references honest when they can only be compared in one place.

## Overview

An image reference only matches the environment that recorded it. Another system version draws
text differently, and even the same simulator build can rasterize a glyph one pixel apart on a
CI machine and on a developer machine. Pick the environment that is the source of truth, record
there and compare there.

### Never write on CI

Set ``SnapshotRecording/never`` for the suites that run on CI. A test that has no reference
then fails without writing anything next to the references, and its snapshot is attached to the
test instead.

This closes the gap that retries open. With a test plan that retries failed tests, a first
attempt that records a reference and fails is followed by a second attempt in the same process,
which finds the file and passes against it. The run is green, and nothing was verified.

``SnapshotRecording/missing`` guards against the same thing on a developer machine: a reference
written by the running process is never accepted by that process.

### Check for references everywhere

A suite that is skipped off CI cannot notice a missing reference. Run it everywhere, and let it
check only for existence where pixels cannot be compared:

```swift
let environment = SnapshotEnvironment(baselineOSVersion: "18.2", policy: .ciOnly)

@MainActor
@Suite(.snapshots(recording: .never, verifying: environment.shouldRun ? .comparison : .referenceExists))
struct ScreenSnapshotTests { ... }
```

With ``SnapshotVerification/referenceExists`` the value is not evaluated and nothing is
rendered, so the check costs next to nothing and runs with every unit test run.

### Read references from the test bundle

Some CI services build on one machine and test on another. The test machine has no checkout, so
the directory of the source file does not exist there. `SnapshotGuard` then reads the references
from the test bundle: add `__Snapshots__` to the test target as resources.

Resources are flattened into the bundle, so reference file names have to be unique across the
whole test target. `snapshot-guard check` reports names that collide.

### Bring recorded references back

Every snapshot that fails is attached to its test as `<kind>~<directory>~<file name>`. The
`snapshot-guard fetch` command reads the attachments of a result bundle and places the recorded
ones under `__Snapshots__`:

```sh
swift run snapshot-guard fetch --xcresult Test.xcresult --snapshots-dir Tests/__Snapshots__
```

After a change that is meant to alter the screens, pass `--include-mismatched` to adopt the
snapshots that did not match. There is no need to delete references first, and so no window in
which they are missing.

Look at every image before committing it.
