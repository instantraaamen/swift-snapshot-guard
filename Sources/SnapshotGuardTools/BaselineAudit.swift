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
import CryptoKit
import Foundation
import ImageIO

/// Problems found in a set of reference images.
public struct BaselineAudit: Equatable, Sendable {
  /// Groups of files with identical bytes. Two different screens that produce the same image
  /// usually means nothing was drawn.
  public var identicalFiles: [[URL]]
  /// Groups of files in different directories that share a file name. They overwrite each
  /// other when references are flattened into a test bundle.
  public var nameCollisions: [[URL]]
  /// Images of one flat colour, which is what a view that drew nothing looks like.
  public var uniformImages: [URL]
  /// The environments the references were recorded in, with the files of each, when there is
  /// more than one. References recorded on different systems cannot all match one test run.
  public var environments: [String: [URL]]

  public var isClean: Bool {
    identicalFiles.isEmpty && nameCollisions.isEmpty && uniformImages.isEmpty
      && environments.isEmpty
  }

  /// Audits the given reference images.
  public static func audit(files: [URL]) throws -> BaselineAudit {
    var byDigest: [String: [URL]] = [:]
    var byName: [String: [URL]] = [:]
    var byEnvironment: [String: [URL]] = [:]
    var uniform: [URL] = []
    for file in files {
      let data = try Data(contentsOf: file)
      let digest = SHA256.hash(data: data)
        .map { String(format: "%02x", $0) }
        .joined()
      byDigest[digest, default: []].append(file)
      byName[file.lastPathComponent, default: []].append(file)
      let image = ReferenceImage(data)
      if image.isUniform { uniform.append(file) }
      if let environment = image.environment {
        byEnvironment[environment, default: []].append(file)
      }
    }
    return BaselineAudit(
      identicalFiles: groups(in: byDigest),
      nameCollisions: groups(in: byName),
      uniformImages: uniform,
      environments: byEnvironment.count > 1 ? byEnvironment : [:]
    )
  }

  /// Audits every PNG under `directory`.
  public static func audit(directory: URL) throws -> BaselineAudit {
    try audit(files: pngFiles(under: directory))
  }

  static func pngFiles(under directory: URL) -> [URL] {
    guard
      let enumerator = FileManager.default.enumerator(
        at: directory, includingPropertiesForKeys: nil)
    else { return [] }
    return
      enumerator
      .compactMap { $0 as? URL }
      .filter { $0.pathExtension.lowercased() == "png" }
      .sorted { $0.path < $1.path }
  }

  private static func groups(in table: [String: [URL]]) -> [[URL]] {
    table.values
      .filter { $0.count > 1 }
      .map { $0.sorted { $0.path < $1.path } }
      .sorted { ($0.count, $1[0].path) > ($1.count, $0[0].path) }
  }
}

/// What the audit reads from one reference image.
struct ReferenceImage {
  /// Whether every pixel has the same colour. `false` for a file that is not an image.
  var isUniform = false
  /// The environment swift-snapshot-guard stored in the file when it recorded it, as a short
  /// description such as `iOS 18.2, iPhone17,1, scale 3.0`.
  var environment: String?

  /// The prefix of the description swift-snapshot-guard writes into a PNG.
  static let marker = "swift-snapshot-guard:"

  init(_ data: Data) {
    guard
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return }
    isUniform = Self.isUniform(image)

    if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let png = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any],
      let description = png[kCGImagePropertyPNGDescription] as? String,
      description.hasPrefix(Self.marker),
      let object = try? JSONSerialization.jsonObject(
        with: Data(description.dropFirst(Self.marker.count).utf8))
        as? [String: Any],
      let system = object["system"] as? String,
      let device = object["device"] as? String,
      let scale = object["scale"] as? Double
    {
      environment = "\(system), \(device), scale \(scale)"
    }
  }

  private static func isUniform(_ image: CGImage) -> Bool {
    let width = image.width
    let height = image.height
    guard width > 0, height > 0, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
      return false
    }
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
          bytesPerRow: width * 4, space: colorSpace,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      context.setBlendMode(.copy)
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drawn else { return false }
    var offset = 4
    while offset < bytes.count {
      if bytes[offset] != bytes[0] || bytes[offset + 1] != bytes[1] || bytes[offset + 2] != bytes[2]
        || bytes[offset + 3] != bytes[3]
      {
        return false
      }
      offset += 4
    }
    return true
  }
}
