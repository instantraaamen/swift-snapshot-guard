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
import UniformTypeIdentifiers

/// Where and with what a reference image was recorded.
///
/// It is stored inside the PNG. When a comparison fails, a reference that was recorded
/// somewhere else explains the failure better than the pixels do: another system version
/// draws text differently, and no change to the app is involved.
public struct RecordingEnvironment: Codable, Equatable, Sendable {
  /// The system and its version, such as `iOS 18.2`.
  public var system: String
  /// The hardware identifier, such as `iPhone17,1`.
  public var device: String
  /// Pixels per point of the image.
  public var scale: Double

  public init(system: String, device: String, scale: Double) {
    self.system = system
    self.device = device
    self.scale = scale
  }

  /// The environment of the current process.
  public static func current(scale: Double) -> RecordingEnvironment {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    #if os(iOS)
      let name = "iOS"
    #elseif os(tvOS)
      let name = "tvOS"
    #elseif os(visionOS)
      let name = "visionOS"
    #else
      let name = "macOS"
    #endif
    var systemInfo = utsname()
    uname(&systemInfo)
    let machine = withUnsafeBytes(of: &systemInfo.machine) { buffer in
      String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }
    // The simulator reports the host's hardware; the simulated model is in the environment.
    let device = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? machine
    return RecordingEnvironment(
      system: "\(name) \(version.majorVersion).\(version.minorVersion)", device: device,
      scale: scale)
  }

  /// A sentence about how this environment differs from `other`, or `nil` when it does not.
  func difference(from other: RecordingEnvironment) -> String? {
    var parts: [String] = []
    if system != other.system { parts.append("\(system) instead of \(other.system)") }
    if device != other.device { parts.append("\(device) instead of \(other.device)") }
    if scale != other.scale { parts.append("scale \(scale) instead of \(other.scale)") }
    return parts.isEmpty ? nil : parts.joined(separator: ", ")
  }
}

/// Reads and writes PNG files.
enum PNG {
  private static let marker = "swift-snapshot-guard:"

  /// Encodes a bitmap as an 8-bit sRGB PNG.
  static func encode(_ bitmap: Bitmap, environment: RecordingEnvironment? = nil) -> Data? {
    guard let image = bitmap.makeImage() else { return nil }
    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        data, UTType.png.identifier as CFString, 1, nil)
    else { return nil }
    var properties: [CFString: Any] = [:]
    if let environment, let json = try? JSONEncoder.sorted.encode(environment) {
      properties[kCGImagePropertyPNGDictionary] = [
        kCGImagePropertyPNGDescription: marker + String(decoding: json, as: UTF8.self)
      ]
    }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return data as Data
  }

  /// Returns the image as a PNG file would hold it.
  ///
  /// A capture from a wide-gamut display has 16-bit floating point components. Converting those
  /// straight to 8-bit sRGB and converting them by way of a PNG file round a small share of the
  /// pixels differently, by one step in a colour channel. References are PNG files, so a
  /// capture is brought into the form a PNG file has before it is compared. That makes a
  /// capture equal, pixel for pixel, to the same capture saved as a PNG by another tool, which
  /// keeps references recorded with other snapshot libraries valid.
  static func quantized(_ image: CGImage) -> CGImage? {
    guard image.bitsPerComponent > 8 else { return image }
    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        data, UTType.png.identifier as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    guard
      CGImageDestinationFinalize(destination),
      let source = CGImageSourceCreateWithData(data, nil)
    else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
  }

  /// Decodes an image file into a bitmap, and reads the environment it was recorded in when
  /// the file carries one.
  static func decode(_ data: Data) -> (bitmap: Bitmap, environment: RecordingEnvironment?)? {
    guard
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let bitmap = Bitmap(image)
    else { return nil }
    var environment: RecordingEnvironment?
    if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let png = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any],
      let description = png[kCGImagePropertyPNGDescription] as? String,
      description.hasPrefix(marker)
    {
      environment = try? JSONDecoder().decode(
        RecordingEnvironment.self, from: Data(description.dropFirst(marker.count).utf8))
    }
    return (bitmap, environment)
  }
}

extension JSONEncoder {
  /// Keys in a fixed order, so that the same value always encodes to the same bytes.
  static var sorted: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }
}
