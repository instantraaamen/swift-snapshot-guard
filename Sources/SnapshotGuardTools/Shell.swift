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

import Foundation

/// An error from an external tool.
public struct ShellError: Error, CustomStringConvertible {
  public var command: String
  public var status: Int32
  public var output: String

  public var description: String {
    "`\(command)` exited with status \(status).\n\(output)"
  }
}

enum Shell {
  @discardableResult
  static func run(_ executable: String, _ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let output = String(decoding: data, as: UTF8.self)
    guard process.terminationStatus == 0 else {
      throw ShellError(
        command: ([executable] + arguments).joined(separator: " "),
        status: process.terminationStatus,
        output: output
      )
    }
    return output
  }
}

/// Reads attachments out of an `.xcresult` bundle.
public enum XCResult {
  /// Exports every attachment in the bundle and returns the manifest.
  ///
  /// Requires the `xcresulttool` that ships with Xcode 16 or later.
  public static func exportAttachments(from xcresult: URL, to directory: URL) throws
    -> [ManifestEntry]
  {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Shell.run(
      "/usr/bin/xcrun",
      [
        "xcresulttool", "export", "attachments", "--path", xcresult.path, "--output-path",
        directory.path,
      ]
    )
    let manifest = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
    return try JSONDecoder().decode([ManifestEntry].self, from: manifest)
  }

  /// Unzips an archive and returns the `.xcresult` bundle inside it.
  public static func unzip(_ archive: URL, to directory: URL) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Shell.run("/usr/bin/ditto", ["-x", "-k", archive.path, directory.path])
    let contents = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)
    guard let bundle = contents.first(where: { $0.pathExtension == "xcresult" }) else {
      throw ShellError(
        command: "ditto", status: 0, output: "No .xcresult bundle in \(archive.lastPathComponent).")
    }
    return bundle
  }
}
