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

@testable import SnapshotGuardTools

@Suite struct BaselineAuditTests {
  private func makeTree(_ files: [String: String]) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    for (path, contents) in files {
      let url = root.appendingPathComponent(path)
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(contents.utf8).write(to: url)
    }
    return root
  }

  @Test func cleanTreeHasNoFindings() throws {
    let root = try makeTree(["A/a.one.png": "1", "B/b.two.png": "2", "B/notes.txt": "1"])
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(try BaselineAudit.audit(directory: root).isClean)
  }

  @Test func reportsIdenticalBytes() throws {
    let root = try makeTree([
      "A/a.one.png": "blank", "B/b.two.png": "blank", "B/b.three.png": "drawn",
    ])
    defer { try? FileManager.default.removeItem(at: root) }
    let audit = try BaselineAudit.audit(directory: root)
    #expect(
      audit.identicalFiles.map { $0.map(\.lastPathComponent) } == [["a.one.png", "b.two.png"]])
    #expect(audit.nameCollisions.isEmpty)
  }

  @Test func reportsNameCollisionsAcrossSuites() throws {
    let root = try makeTree(["A/test.Screen.png": "1", "B/test.Screen.png": "2"])
    defer { try? FileManager.default.removeItem(at: root) }
    let audit = try BaselineAudit.audit(directory: root)
    #expect(audit.nameCollisions.count == 1)
    #expect(audit.identicalFiles.isEmpty)
  }

  private func png(_ pixel: (Int, Int) -> (UInt8, UInt8, UInt8), description: String? = nil) throws
    -> Data
  {
    let size = 4
    var bytes: [UInt8] = []
    for y in 0..<size {
      for x in 0..<size {
        let (red, green, blue) = pixel(x, y)
        bytes += [red, green, blue, 255]
      }
    }
    let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
    let image = try #require(
      CGImage(
        width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
        space: colorSpace,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let data = NSMutableData()
    let destination = try #require(
      CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
    var properties: [CFString: Any] = [:]
    if let description {
      properties[kCGImagePropertyPNGDictionary] = [kCGImagePropertyPNGDescription: description]
    }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
  }

  private func write(_ files: [String: Data]) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    for (path, data) in files {
      let url = root.appendingPathComponent(path)
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: url)
    }
    return root
  }

  /// A view that fails to draw produces a flat image, and a flat image matches a flat
  /// reference on every run after that.
  @Test func reportsImagesOfOneFlatColour() throws {
    let root = try write([
      "A/a.blank.png": try png { _, _ in (255, 255, 255) },
      "A/a.drawn.png": try png { x, y in (UInt8(x * 60), UInt8(y * 60), 0) },
    ])
    defer { try? FileManager.default.removeItem(at: root) }
    let audit = try BaselineAudit.audit(directory: root)
    #expect(audit.uniformImages.map(\.lastPathComponent) == ["a.blank.png"])
  }

  /// References recorded on two system versions cannot all match one test run.
  @Test func reportsReferencesFromMoreThanOneEnvironment() throws {
    func environment(_ system: String) -> String {
      #"swift-snapshot-guard:{"device":"iPhone17,1","scale":3,"system":"\#(system)"}"#
    }
    let drawn: (Int, Int) -> (UInt8, UInt8, UInt8) = { x, y in (UInt8(x * 60), UInt8(y * 60), 0) }
    let mixed = try write([
      "A/a.one.png": try png(drawn, description: environment("iOS 18.1")),
      "A/a.two.png": try png(
        { x, y in (UInt8(y * 60), UInt8(x * 60), 9) }, description: environment("iOS 18.2")),
      "A/a.three.png": try png({ x, y in (UInt8(y * 50), UInt8(x * 50), 7) }),
    ])
    defer { try? FileManager.default.removeItem(at: mixed) }
    let audit = try BaselineAudit.audit(directory: mixed)
    #expect(
      audit.environments.keys.sorted() == [
        "iOS 18.1, iPhone17,1, scale 3.0", "iOS 18.2, iPhone17,1, scale 3.0",
      ])

    let single = try write(["A/a.one.png": try png(drawn, description: environment("iOS 18.2"))])
    defer { try? FileManager.default.removeItem(at: single) }
    #expect(try BaselineAudit.audit(directory: single).isClean)
  }
}
