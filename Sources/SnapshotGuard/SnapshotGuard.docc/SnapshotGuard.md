# ``SnapshotGuard``

Snapshot tests for Swift Testing that cannot pass by accident.

## Overview

A snapshot test compares what a value looks like now with a reference that was recorded
earlier. `SnapshotGuard` takes the snapshot, finds the reference and compares the two, and it is
built around one rule: a test never passes without having compared something.

```swift
@MainActor
@Suite(.snapshots(recording: .never))
struct ProfileSnapshotTests {
  @Test func profile() async {
    await expectSnapshot(
      of: ProfileView(user: .sample),
      as: .image(layout: .fixed(width: 390, height: 844))
    )
  }
}
```

## Topics

### Essentials

- ``expectSnapshot(of:as:named:testName:fileID:filePath:function:line:column:)``
- ``requireSnapshot(of:as:named:testName:fileID:filePath:function:line:column:)``
- <doc:RunningOnCI>

### Configuring a suite

- ``SnapshotsTrait``
- ``SnapshotConfiguration``
- ``SnapshotRecording``
- ``SnapshotVerification``
- ``SnapshotDirectory``

### Taking snapshots

- ``SnapshotStrategy``
- ``ImageTolerance``
- ``RecordingEnvironment``

### Understanding failures

- ``SnapshotFailure``
- ``SnapshotMismatch``
- ``SnapshotAttachment``

### Running where the references were recorded

- ``SnapshotEnvironment``
- ``withCleanUserDefaults(_:domain:_:)-(_,_,()->Result)``
