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

/// How much two images may differ and still count as the same.
///
/// The default is none: every pixel has to match. Loosen it for a screen that cannot be made
/// to draw the same way twice, such as one with a spinner caught mid-turn, and prefer
/// ``ignoredRegions`` over a tolerance that covers the whole image.
public struct ImageTolerance: Equatable, Sendable {
  /// The share of pixels that may differ, from `0` to `1`.
  public var differingPixelShare: Double
  /// How far a colour channel of a pixel may be off, from `0` to `255`, before the pixel counts
  /// as differing. `1` absorbs rounding between two renderings of the same colour.
  public var channelDelta: Int
  /// Areas that are left out of the comparison, in points from the top left of the image.
  public var ignoredRegions: [CGRect]

  public init(differingPixelShare: Double = 0, channelDelta: Int = 0, ignoredRegions: [CGRect] = [])
  {
    self.differingPixelShare = differingPixelShare
    self.channelDelta = channelDelta
    self.ignoredRegions = ignoredRegions
  }

  /// Every pixel has to match.
  public static let exact = ImageTolerance()

  /// A share of the pixels may differ.
  public static func pixels(_ share: Double) -> ImageTolerance {
    ImageTolerance(differingPixelShare: share)
  }

  /// Returns the tolerance with areas left out of the comparison.
  public func ignoring(_ regions: CGRect...) -> ImageTolerance {
    var tolerance = self
    tolerance.ignoredRegions += regions
    return tolerance
  }
}
