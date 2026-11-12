// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "swift-snapshot-guard",
  platforms: [
    .iOS(.v15),
    .macOS(.v13),
    .tvOS(.v15),
  ],
  products: [
    .library(name: "SnapshotGuard", targets: ["SnapshotGuard"]),
    .executable(name: "snapshot-guard", targets: ["snapshot-guard"]),
  ],
  dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
  ],
  targets: [
    .target(
      name: "SnapshotGuard",
      dependencies: [
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
      ]
    ),
    .target(name: "SnapshotGuardCore"),
    .executableTarget(
      name: "snapshot-guard",
      dependencies: [
        "SnapshotGuardCore",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),
    .testTarget(name: "SnapshotGuardTests", dependencies: ["SnapshotGuard"]),
    .testTarget(name: "SnapshotGuardCoreTests", dependencies: ["SnapshotGuardCore"]),
  ]
)
