# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-11-13

### Added

- `expectSnapshot` and `requireSnapshot`, for Swift Testing.
- Image strategies for SwiftUI views, `UIView`, `UIViewController` and `CGImage`, and strategies for text and data.
- Views are drawn through a window of their own in the host application, with a fixed size and safe area.
- The `.snapshots` trait, with `recording`, `verifying`, `directory` and `imageTolerance`.
- `SnapshotRecording.never`, which attaches a missing reference instead of writing it.
- A reference recorded by the running process is never accepted by it.
- `SnapshotVerification.referenceExists`, which checks that references exist without rendering.
- Pixel comparison in 8-bit sRGB, with a tolerance in pixels, a channel delta and ignored regions.
- Rejection of images of one flat colour.
- The recording environment is stored in every reference and reported when it differs.
- `SnapshotSettling`, to wait for the main queue, a condition or a delay before a snapshot.
- `SnapshotEnvironment` and `withCleanUserDefaults`.
- `snapshot-guard fetch`, which places attached snapshots from a result bundle or an Xcode Cloud build, and `--include-mismatched` to adopt changed screens.
- `snapshot-guard check`, which reports identical, flat and colliding references and mixed recording environments.
- The App Store Connect token is only sent to the host of the API over HTTPS. A page link that points elsewhere is refused.

[Unreleased]: https://github.com/instantraaamen/swift-snapshot-guard/compare/0.1.0...HEAD
[0.1.0]: https://github.com/instantraaamen/swift-snapshot-guard/releases/tag/0.1.0
