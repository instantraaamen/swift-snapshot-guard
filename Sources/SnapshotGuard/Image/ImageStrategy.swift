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

/// An image with the number of pixels it has per point.
struct RenderedImage {
  var image: CGImage
  var scale: Double
}

extension SnapshotStrategy where Value == CGImage {
  /// Stores the image as an 8-bit sRGB PNG and compares pixels.
  ///
  /// - Parameters:
  ///   - tolerance: How much the image may differ from its reference. `nil` uses
  ///     ``SnapshotConfiguration/imageTolerance``.
  ///   - scale: Pixels per point. It places ``ImageTolerance/ignoredRegions`` and is stored
  ///     with the reference.
  ///   - allowsUniformImage: Whether an image of one flat colour is accepted. It is rejected
  ///     by default, because that is what a view that failed to draw looks like.
  public static func image(
    tolerance: ImageTolerance? = nil,
    scale: Double = 1,
    allowsUniformImage: Bool = false
  ) -> SnapshotStrategy {
    SnapshotStrategy<RenderedImage>.rendered(
      tolerance: tolerance, allowsUniformImage: allowsUniformImage
    )
    .pullback { RenderedImage(image: $0, scale: scale) }
  }
}

extension SnapshotStrategy where Value == RenderedImage {
  static func rendered(tolerance: ImageTolerance?, allowsUniformImage: Bool) -> SnapshotStrategy {
    SnapshotStrategy(
      pathExtension: "png",
      validate: { actual in
        guard !allowsUniformImage, let decoded = PNG.decode(actual), decoded.bitmap.isUniform else {
          return nil
        }
        return "the image is one flat colour, which is what a view that drew nothing looks like. "
          + "Pass `allowsUniformImage: true` if that is what it should show."
      },
      compare: { reference, actual, configuration in
        ImageMismatch.describe(
          reference: reference, actual: actual, tolerance: tolerance ?? configuration.imageTolerance
        )
      },
      encode: { rendered, _ in
        guard
          let quantized = PNG.quantized(rendered.image),
          let bitmap = Bitmap(quantized),
          let data = PNG.encode(bitmap, environment: .current(scale: rendered.scale))
        else { throw ImageEncodingError() }
        return data
      }
    )
  }
}

struct ImageEncodingError: Error, CustomStringConvertible {
  var description: String { "the image could not be encoded as a PNG" }
}

enum ImageMismatch {
  /// Compares two image files. Returns `nil` when they match within the tolerance.
  static func describe(reference: Data, actual: Data, tolerance: ImageTolerance)
    -> SnapshotMismatch?
  {
    // Byte-identical files need no decoding.
    if reference == actual { return nil }
    guard let old = PNG.decode(reference) else {
      return SnapshotMismatch(message: "The reference is not an image that can be read.")
    }
    guard let new = PNG.decode(actual) else {
      return SnapshotMismatch(message: "The snapshot is not an image that can be read.")
    }
    let attachments = [
      SnapshotAttachment(kind: .actual, data: actual, pathExtension: "png"),
      SnapshotAttachment(kind: .reference, data: reference, pathExtension: "png"),
    ]
    let environment = environmentNote(reference: old.environment, actual: new.environment)

    guard
      let comparison = ImageComparison(
        reference: old.bitmap, actual: new.bitmap, tolerance: tolerance,
        scale: CGFloat(new.environment?.scale ?? 1))
    else {
      return SnapshotMismatch(
        message:
          "The image is \(new.bitmap.width)×\(new.bitmap.height) pixels and the reference is "
          + "\(old.bitmap.width)×\(old.bitmap.height)." + environment,
        attachments: attachments)
    }
    guard !comparison.matches else { return nil }

    var all = attachments
    if let difference = ImageComparison.differenceImage(
      reference: old.bitmap, actual: new.bitmap, tolerance: tolerance),
      let data = PNG.encode(difference)
    {
      all.append(SnapshotAttachment(kind: .difference, data: data, pathExtension: "png"))
    }
    let message =
      "\(comparison.differingPixelCount) of \(comparison.comparedPixelCount) pixels differ "
      + "(\(percent(comparison.differingPixelShare)), allowed \(percent(tolerance.differingPixelShare))). "
      + "The largest difference in a colour channel is \(comparison.largestChannelDelta) of 255."
    return SnapshotMismatch(message: message + environment, attachments: all)
  }

  private static func percent(_ share: Double) -> String {
    String(format: "%.3f%%", share * 100)
  }

  private static func environmentNote(
    reference: RecordingEnvironment?, actual: RecordingEnvironment?
  ) -> String {
    guard let reference, let actual, let difference = actual.difference(from: reference) else {
      return ""
    }
    return " The reference was recorded in another environment (this run: \(difference)). "
      + "Text and effects are drawn differently from one system or device to the next, "
      + "so record the reference again where the tests run."
  }
}
