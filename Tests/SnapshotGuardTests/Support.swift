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

import CoreGraphics
import Foundation
import Testing

@testable import SnapshotGuard

/// A bitmap whose pixels come from a closure. The colour is `(red, green, blue, alpha)`.
func makeBitmap(
  width: Int = 8, height: Int = 8,
  _ pixel: (_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8, UInt8) = { x, y in
    (UInt8(x * 20), UInt8(y * 20), 90, 255)
  }
) -> Bitmap {
  var bytes: [UInt8] = []
  bytes.reserveCapacity(width * height * 4)
  for y in 0..<height {
    for x in 0..<width {
      let (red, green, blue, alpha) = pixel(x, y)
      bytes += [red, green, blue, alpha]
    }
  }
  return Bitmap(width: width, height: height, bytes: bytes)
}

func makeImage(
  width: Int = 8, height: Int = 8,
  _ pixel: (_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8, UInt8) = { x, y in
    (UInt8(x * 20), UInt8(y * 20), 90, 255)
  }
) -> CGImage {
  makeBitmap(width: width, height: height, pixel).makeImage()!
}

/// A directory that is removed when the value goes away.
final class TemporaryDirectory {
  let url: URL

  init() {
    url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "snapshot-guard-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  deinit { try? FileManager.default.removeItem(at: url) }

  var files: [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
  }
}

/// Runs the decision of a snapshot test against a directory, without reporting to the test
/// framework, so that failures can be inspected.
@MainActor
func verify<Value>(
  _ value: Value,
  as strategy: SnapshotStrategy<Value>,
  named name: String? = "shot",
  in directory: TemporaryDirectory,
  recording: SnapshotRecording = .missing,
  verification: SnapshotVerification = .comparison,
  imageTolerance: ImageTolerance = .exact
) async -> SnapshotFailure? {
  let configuration = SnapshotConfiguration(
    recording: recording, verification: verification, directory: .at(directory.url),
    imageTolerance: imageTolerance)
  return await snapshotFailure(
    of: value, as: strategy, named: name, testName: "test()", filePath: #filePath,
    function: #function,
    configuration: configuration)
}
