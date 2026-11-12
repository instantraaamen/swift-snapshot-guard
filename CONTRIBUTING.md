# Contributing

Thank you for helping out.

## Before you open a pull request

- Open an issue first for anything larger than a small fix, so the approach can be agreed on.
- Run `swift test`. The package builds for iOS as well; `xcodebuild build -scheme SnapshotGuard -destination 'generic/platform=iOS Simulator'` checks that.
- Run `swift format lint --strict -r Sources Tests Package.swift`. `swift format -i -r Sources Tests Package.swift` fixes most findings.
- Add or update tests for the behaviour you change. Every way a snapshot test once passed without verifying anything has a test that reproduces it; a new one gets a test too, with a comment that says what went wrong.
- Add a line to the Unreleased section of `CHANGELOG.md`.

## Style

- Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
- Public API follows Swift Testing: `expectSnapshot` and `requireSnapshot` behave like `#expect` and `#require`, and settings are traits.
- The `SnapshotGuard` target depends on the Swift toolchain and Apple's frameworks only.
- A snapshot test must never pass without having compared something. When in doubt, fail and say why.
- Every source file starts with the license header. Copy it from an existing file.
- Write code, comments, commits and issues in English.

## License

By contributing, you agree that your contribution is licensed under the Apache License 2.0.

## Reviews

Pull requests from branches in this repository get an automated review comment in addition to a maintainer's review. Pull requests from forks do not, because the workflow has no access to secrets there; a maintainer reviews those by hand.
