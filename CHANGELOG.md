# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `assertGuardedSnapshot` and `verifyGuardedSnapshot`, which fail a retry that would otherwise pass against a reference recorded earlier in the same test run.
- `SnapshotGuard.missingReferenceCheck()` to notice when swift-snapshot-testing changes its missing-reference message.
- `Snapshotting.keyWindowImage` for SwiftUI views.
- `SnapshotEnvironment`, `SnapshotDirectory` and `withCleanUserDefaults`.
- `snapshot-guard fetch` to copy recorded snapshots out of a result bundle, from disk or from Xcode Cloud.
- `snapshot-guard check` to report identical images and file name collisions.
