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
import ImageIO
import Testing

@testable import SnapshotGuard

@Suite struct ImageComparisonTests {
  @Test func identicalImagesMatch() throws {
    let bitmap = makeBitmap()
    let comparison = try #require(
      ImageComparison(reference: bitmap, actual: bitmap, tolerance: .exact))
    #expect(comparison.matches)
    #expect(comparison.comparedPixelCount == 64)
    #expect(comparison.differingPixelCount == 0)
    #expect(comparison.largestChannelDelta == 0)
  }

  @Test func oneDifferentPixelFailsAnExactComparison() throws {
    let reference = makeBitmap()
    let actual = makeBitmap { x, y in
      x == 3 && y == 5 ? (0, 0, 0, 255) : (UInt8(x * 20), UInt8(y * 20), 90, 255)
    }
    let comparison = try #require(
      ImageComparison(reference: reference, actual: actual, tolerance: .exact))
    #expect(!comparison.matches)
    #expect(comparison.differingPixelCount == 1)
    #expect(comparison.largestChannelDelta == 100)
  }

  @Test func theShareOfPixelsIsCountedInPixelsNotBytes() throws {
    // 100 pixels, of which 2 differ in every channel: 2%, however many bytes that is.
    let reference = makeBitmap(width: 10, height: 10) { _, _ in (10, 20, 30, 255) }
    let actual = makeBitmap(width: 10, height: 10) { x, y in
      y == 0 && x < 2 ? (200, 200, 200, 255) : (10, 20, 30, 255)
    }
    #expect(
      try #require(ImageComparison(reference: reference, actual: actual, tolerance: .pixels(0.02)))
        .matches)
    #expect(
      try !#require(
        ImageComparison(reference: reference, actual: actual, tolerance: .pixels(0.019))
      ).matches)
  }

  @Test func aChannelDeltaAbsorbsRounding() throws {
    let reference = makeBitmap { _, _ in (100, 100, 100, 255) }
    let actual = makeBitmap { _, _ in (101, 99, 100, 255) }
    #expect(
      try !#require(ImageComparison(reference: reference, actual: actual, tolerance: .exact))
        .matches)
    let tolerant = try #require(
      ImageComparison(
        reference: reference, actual: actual, tolerance: ImageTolerance(channelDelta: 1)))
    #expect(tolerant.matches)
    #expect(tolerant.largestChannelDelta == 1)
  }

  @Test func differentSizesCannotBeCompared() {
    #expect(
      ImageComparison(
        reference: makeBitmap(width: 8, height: 8), actual: makeBitmap(width: 8, height: 9),
        tolerance: .exact)
        == nil)
  }

  /// A spinner draws at another angle every time. Leaving its area out keeps the rest of the
  /// screen under an exact comparison, instead of loosening the tolerance for all of it.
  @Test func ignoredRegionsAreLeftOut() throws {
    let reference = makeBitmap(width: 20, height: 20) { _, _ in (255, 255, 255, 255) }
    let actual = makeBitmap(width: 20, height: 20) { x, y in
      (4..<8).contains(x) && (4..<8).contains(y) ? (0, 0, 0, 255) : (255, 255, 255, 255)
    }
    #expect(
      try !#require(ImageComparison(reference: reference, actual: actual, tolerance: .exact))
        .matches)

    // The region is in points; at two pixels per point it covers pixels 4 to 8.
    let tolerance = ImageTolerance.exact.ignoring(CGRect(x: 2, y: 2, width: 2, height: 2))
    let comparison = try #require(
      ImageComparison(reference: reference, actual: actual, tolerance: tolerance, scale: 2))
    #expect(comparison.matches)
    #expect(comparison.comparedPixelCount == 400 - 16)
  }

  @Test func theDifferenceImageMarksWhatDiffers() throws {
    let reference = makeBitmap { _, _ in (0, 0, 0, 255) }
    let actual = makeBitmap { x, y in x == 0 && y == 0 ? (255, 255, 255, 255) : (0, 0, 0, 255) }
    let difference = try #require(
      ImageComparison.differenceImage(reference: reference, actual: actual, tolerance: .exact))
    #expect(Array(difference.bytes[0..<4]) == [255, 0, 0, 255])
    #expect(Array(difference.bytes[4..<8]) == [192, 192, 192, 255])
  }

  @Test func aFlatImageIsRecognised() {
    #expect(makeBitmap { _, _ in (255, 255, 255, 255) }.isUniform)
    #expect(!makeBitmap { x, _ in x == 7 ? (254, 255, 255, 255) : (255, 255, 255, 255) }.isUniform)
  }
}

@Suite struct PNGTests {
  @Test func aBitmapSurvivesARoundTripWithItsEnvironment() throws {
    let bitmap = makeBitmap()
    let environment = RecordingEnvironment(system: "iOS 18.2", device: "iPhone17,1", scale: 3)
    let data = try #require(PNG.encode(bitmap, environment: environment))
    let decoded = try #require(PNG.decode(data))
    #expect(decoded.bitmap == bitmap)
    #expect(decoded.environment == environment)
  }

  @Test func aPNGWithoutAnEnvironmentIsRead() throws {
    let data = try #require(PNG.encode(makeBitmap()))
    let decoded = try #require(PNG.decode(data))
    #expect(decoded.environment == nil)
  }

  @Test func encodingIsStable() throws {
    let environment = RecordingEnvironment(system: "iOS 18.2", device: "iPhone17,1", scale: 3)
    #expect(
      PNG.encode(makeBitmap(), environment: environment)
        == PNG.encode(makeBitmap(), environment: environment))
  }

  /// A capture from a wide-gamut display and a file read back from disk hold the same picture
  /// in different colour spaces and depths. Comparing their raw bytes once reported an 8%
  /// difference for images that were 0.16% apart.
  @Test func aWideGamutSixteenBitImageComparesEqualToItsSRGBForm() throws {
    let bitmap = makeBitmap(width: 16, height: 16) { x, y in
      (UInt8(x * 16), UInt8(y * 16), 128, 255)
    }
    let sRGBImage = try #require(bitmap.makeImage())

    // The same picture, converted to 16-bit Display P3.
    let displayP3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
    let context = try #require(
      CGContext(
        data: nil, width: 16, height: 16, bitsPerComponent: 16, bytesPerRow: 0, space: displayP3,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(sRGBImage, in: CGRect(x: 0, y: 0, width: 16, height: 16))
    let wideImage = try #require(context.makeImage())
    #expect(wideImage.bitsPerComponent == 16)

    let converted = try #require(Bitmap(wideImage))
    let comparison = try #require(
      ImageComparison(
        reference: bitmap, actual: converted, tolerance: ImageTolerance(channelDelta: 1)))
    #expect(comparison.matches)
    #expect(comparison.largestChannelDelta <= 1)
  }

  /// A capture and the same capture saved as a PNG by another library must compare equal in
  /// every pixel, or references recorded with that library stop matching by a rounding step.
  @MainActor
  @Test func aDeepCaptureEqualsTheSameCaptureSavedAsAPNG() async throws {
    // A 16-bit floating point image in extended sRGB, which is what a wide-gamut capture is.
    let space = try #require(CGColorSpace(name: CGColorSpace.extendedSRGB))
    let info =
      CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue
      | CGBitmapInfo.byteOrder16Little.rawValue
    let context = try #require(
      CGContext(
        data: nil, width: 64, height: 64, bitsPerComponent: 16, bytesPerRow: 0, space: space,
        bitmapInfo: info))
    for y in 0..<64 {
      for x in 0..<64 {
        context.setFillColor(
          red: CGFloat(x) / 63 * 1.1 - 0.05, green: CGFloat(y) / 63, blue: CGFloat(x + y) / 126,
          alpha: 1)
        context.fill(CGRect(x: x, y: y, width: 1, height: 1))
      }
    }
    let capture = try #require(context.makeImage())
    #expect(capture.bitsPerComponent == 16)

    // What another library stores: the capture, written as a PNG.
    let stored = NSMutableData()
    let destination = try #require(
      CGImageDestinationCreateWithData(stored, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, capture, nil)
    #expect(CGImageDestinationFinalize(destination))
    let reference = try #require(PNG.decode(stored as Data))

    // What this library produces from the same capture.
    let strategy = SnapshotStrategy<CGImage>.image()
    let actual = try #require(
      PNG.decode(try await strategy.encode(capture, SnapshotConfiguration())))

    let comparison = try #require(
      ImageComparison(reference: reference.bitmap, actual: actual.bitmap, tolerance: .exact))
    #expect(comparison.differingPixelCount == 0)
  }

  @Test func environmentsDescribeHowTheyDiffer() {
    let recorded = RecordingEnvironment(system: "iOS 18.1", device: "iPhone16,1", scale: 3)
    #expect(recorded.difference(from: recorded) == nil)
    let now = RecordingEnvironment(system: "iOS 18.2", device: "iPhone16,1", scale: 2)
    #expect(
      now.difference(from: recorded) == "iOS 18.2 instead of iOS 18.1, scale 2.0 instead of 3.0")
  }
}
