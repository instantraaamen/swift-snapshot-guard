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

/// The result of comparing two images.
struct ImageComparison: Equatable, Sendable {
  /// How many pixels were compared, which leaves out the ignored regions.
  var comparedPixelCount: Int
  /// How many of them differ by more than the tolerated channel delta.
  var differingPixelCount: Int
  /// The largest difference found in any colour channel of any compared pixel, from 0 to 255.
  var largestChannelDelta: Int
  /// How many pixels the tolerance allows to differ.
  var allowedPixelCount: Int

  var differingPixelShare: Double {
    comparedPixelCount > 0 ? Double(differingPixelCount) / Double(comparedPixelCount) : 0
  }

  var matches: Bool { differingPixelCount <= allowedPixelCount }

  /// Compares two bitmaps of the same size.
  ///
  /// - Parameters:
  ///   - scale: Pixels per point, to place ``ImageTolerance/ignoredRegions``.
  /// - Returns: `nil` when the sizes differ.
  init?(reference: Bitmap, actual: Bitmap, tolerance: ImageTolerance, scale: CGFloat = 1) {
    guard reference.width == actual.width, reference.height == actual.height else { return nil }
    let width = reference.width
    let height = reference.height
    let ignored = Self.ignoredRows(
      tolerance.ignoredRegions, scale: scale, width: width, height: height)

    var compared = 0
    var differing = 0
    var largest = 0

    // Identical bytes are the common case, and need no per-pixel work.
    if ignored.isEmpty, reference.bytes == actual.bytes {
      compared = width * height
    } else {
      reference.bytes.withUnsafeBufferPointer { old in
        actual.bytes.withUnsafeBufferPointer { new in
          for y in 0..<height {
            let skipped = ignored[y] ?? []
            var x = 0
            while x < width {
              if let range = skipped.first(where: { $0.contains(x) }) {
                x = range.upperBound
                continue
              }
              let offset = (y * width + x) * Bitmap.bytesPerPixel
              var delta = 0
              for channel in 0..<Bitmap.bytesPerPixel {
                delta = max(delta, abs(Int(old[offset + channel]) - Int(new[offset + channel])))
              }
              compared += 1
              largest = max(largest, delta)
              if delta > tolerance.channelDelta { differing += 1 }
              x += 1
            }
          }
        }
      }
    }

    comparedPixelCount = compared
    differingPixelCount = differing
    largestChannelDelta = largest
    allowedPixelCount = Int((Double(compared) * tolerance.differingPixelShare).rounded(.down))
  }

  /// The ignored columns of every row that has any, as pixel ranges.
  private static func ignoredRows(
    _ regions: [CGRect], scale: CGFloat, width: Int, height: Int
  ) -> [Int: [Range<Int>]] {
    var rows: [Int: [Range<Int>]] = [:]
    for region in regions {
      let minX = max(0, Int((region.minX * scale).rounded(.down)))
      let maxX = min(width, Int((region.maxX * scale).rounded(.up)))
      let minY = max(0, Int((region.minY * scale).rounded(.down)))
      let maxY = min(height, Int((region.maxY * scale).rounded(.up)))
      guard minX < maxX, minY < maxY else { continue }
      for y in minY..<maxY {
        rows[y, default: []].append(minX..<maxX)
      }
    }
    return rows
  }

  /// An image that shows where two bitmaps of the same size differ: the actual image, faded,
  /// with every differing pixel in red.
  static func differenceImage(reference: Bitmap, actual: Bitmap, tolerance: ImageTolerance)
    -> Bitmap?
  {
    guard reference.width == actual.width, reference.height == actual.height else { return nil }
    var bytes = [UInt8](repeating: 255, count: actual.bytes.count)
    var offset = 0
    while offset < bytes.count {
      var delta = 0
      for channel in 0..<Bitmap.bytesPerPixel {
        delta = max(
          delta, abs(Int(reference.bytes[offset + channel]) - Int(actual.bytes[offset + channel])))
      }
      if delta > tolerance.channelDelta {
        bytes[offset] = 255
        bytes[offset + 1] = 0
        bytes[offset + 2] = 0
      } else {
        // Three quarters of the way to white, so that the red stands out.
        for channel in 0..<3 {
          bytes[offset + channel] = UInt8(255 - (255 - Int(actual.bytes[offset + channel])) / 4)
        }
      }
      offset += Bitmap.bytesPerPixel
    }
    return Bitmap(width: actual.width, height: actual.height, bytes: bytes)
  }
}
