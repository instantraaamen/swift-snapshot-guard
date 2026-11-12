// swift-tools-version: 6.2
//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-snapshot-guard open source project
//
// Copyright (c) 2026 the swift-snapshot-guard project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import PackageDescription

let package = Package(
  name: "swift-snapshot-guard",
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
    .tvOS(.v17),
    .visionOS(.v1),
  ],
  products: [
    // Goes into a test target: takes snapshots and compares them with their references.
    .library(name: "SnapshotGuard", targets: ["SnapshotGuard"]),
    // What the command line tool is built from, for your own tooling.
    .library(name: "SnapshotGuardTools", targets: ["SnapshotGuardTools"]),
    .executable(name: "snapshot-guard", targets: ["snapshot-guard"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
  ],
  targets: [
    .target(name: "SnapshotGuard"),
    .target(name: "SnapshotGuardTools"),
    .target(name: "SnapshotGuardXcodeCloud", dependencies: ["SnapshotGuardTools"]),
    .executableTarget(
      name: "snapshot-guard",
      dependencies: [
        "SnapshotGuardTools",
        "SnapshotGuardXcodeCloud",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ]
    ),
    .testTarget(name: "SnapshotGuardTests", dependencies: ["SnapshotGuard"]),
    .testTarget(name: "SnapshotGuardToolsTests", dependencies: ["SnapshotGuardTools"]),
    .testTarget(name: "SnapshotGuardXcodeCloudTests", dependencies: ["SnapshotGuardXcodeCloud"]),
  ]
)
