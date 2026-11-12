# Security Policy

Please report vulnerabilities through [GitHub private vulnerability reporting](https://github.com/instantraaamen/swift-snapshot-guard/security/advisories/new) rather than a public issue.

`snapshot-guard fetch --xcode-cloud` reads an App Store Connect API key from the environment and sends a short-lived token signed with it to `api.appstoreconnect.apple.com` only. The key is never written to disk or logged.
