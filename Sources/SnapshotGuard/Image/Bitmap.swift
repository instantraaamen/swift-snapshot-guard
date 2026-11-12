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

/// An image as sRGB bytes: four per pixel, red, green, blue and alpha, with colour
/// premultiplied by alpha.
///
/// Every image is brought into this one form before it is compared. Two images of the same
/// content can arrive in different colour spaces and bit depths, for example a wide-gamut
/// capture and a PNG that was read back from disk, and comparing their raw bytes would report
/// a difference where there is none.
struct Bitmap: Equatable, Sendable {
  var width: Int
  var height: Int
  var bytes: [UInt8]

  static let bytesPerPixel = 4

  init(width: Int, height: Int, bytes: [UInt8]) {
    precondition(bytes.count == width * height * Self.bytesPerPixel)
    self.width = width
    self.height = height
    self.bytes = bytes
  }

  /// Draws the image into an sRGB bitmap, converting its colours.
  init?(_ image: CGImage) {
    let width = image.width
    let height = image.height
    guard width > 0, height > 0, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
      return nil
    }
    var bytes = [UInt8](repeating: 0, count: width * height * Self.bytesPerPixel)
    let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress,
          width: width,
          height: height,
          bitsPerComponent: 8,
          bytesPerRow: width * Self.bytesPerPixel,
          space: colorSpace,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
      else { return false }
      // Copy, do not blend and do not resample: the bytes must be the image's own.
      context.setBlendMode(.copy)
      context.interpolationQuality = .none
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drawn else { return nil }
    self.init(width: width, height: height, bytes: bytes)
  }

  /// Makes an image from the bytes.
  func makeImage() -> CGImage? {
    guard
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let provider = CGDataProvider(data: Data(bytes) as CFData)
    else { return nil }
    return CGImage(
      width: width,
      height: height,
      bitsPerComponent: 8,
      bitsPerPixel: 32,
      bytesPerRow: width * Self.bytesPerPixel,
      space: colorSpace,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent
    )
  }

  /// Whether every pixel has the same colour, which is what a view that drew nothing looks like.
  var isUniform: Bool {
    guard bytes.count >= Self.bytesPerPixel else { return true }
    let first = bytes[0..<Self.bytesPerPixel]
    var offset = Self.bytesPerPixel
    while offset < bytes.count {
      if bytes[offset] != first[0] || bytes[offset + 1] != first[1] || bytes[offset + 2] != first[2]
        || bytes[offset + 3] != first[3]
      {
        return false
      }
      offset += Self.bytesPerPixel
    }
    return true
  }
}
