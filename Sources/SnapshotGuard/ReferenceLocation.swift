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

/// Where the reference of one snapshot is read from and written to.
struct ReferenceLocation: Equatable, Sendable {
  /// The reference file name, such as `profile.Profile_en.png`.
  var fileName: String
  /// The name of the directory that groups the references of one source file. It goes into
  /// attachment names, so that `snapshot-guard fetch` knows where a recorded file belongs.
  var directoryName: String
  /// The places a reference is looked for, in order.
  var candidates: [URL]
  /// The place a reference is written to, or `nil` when there is none here.
  var writable: URL?

  /// A dependency seam for tests.
  struct FileSystem: Sendable {
    var directoryExists: @Sendable (String) -> Bool
    var bundleResource: @Sendable (_ name: String, _ pathExtension: String) -> URL?

    static let live = FileSystem(
      directoryExists: { path in
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
          && isDirectory.boolValue
      },
      bundleResource: { name, pathExtension in
        // The bundle that holds the tests. Resources of a test bundle are found flat in it.
        Bundle.allBundles.first { $0.bundleURL.pathExtension == "xctest" }?
          .url(forResource: name, withExtension: pathExtension)
      }
    )
  }

  init(
    directory: SnapshotDirectory,
    testName: String,
    snapshotName: String,
    pathExtension: String,
    fileSystem: FileSystem = .live
  ) {
    let stem = "\(Self.sanitize(testName)).\(Self.sanitize(snapshotName))"
    fileName = pathExtension.isEmpty ? stem : "\(stem).\(pathExtension)"

    switch directory.storage {
    case .fixed(let url):
      directoryName = url.lastPathComponent
      candidates = [url.appendingPathComponent(fileName)]
      writable = candidates.first

    case .nextToSourceFile(let path):
      let source = URL(fileURLWithPath: path)
      directoryName = source.deletingPathExtension().lastPathComponent
      let sourceDirectory = source.deletingLastPathComponent()
      if fileSystem.directoryExists(sourceDirectory.path) {
        // The checkout is here. It is the only place that counts: a reference that only exists
        // in the test bundle has not been added to the repository.
        let url =
          sourceDirectory
          .appendingPathComponent("__Snapshots__")
          .appendingPathComponent(directoryName)
          .appendingPathComponent(fileName)
        candidates = [url]
        writable = url
      } else {
        // No checkout, as on a CI machine that only runs the tests. Read what was copied into
        // the test bundle; there is nowhere to record to.
        candidates = [fileSystem.bundleResource(stem, pathExtension)].compactMap { $0 }
        writable = nil
      }
    }
  }

  /// Makes a name safe to use in a file name: runs of characters other than letters, digits
  /// and underscores become one hyphen. `profile()` becomes `profile`.
  static func sanitize(_ name: String) -> String {
    var result = ""
    var pendingHyphen = false
    for character in name {
      if character.isLetter || character.isNumber || character == "_" {
        if pendingHyphen, !result.isEmpty { result.append("-") }
        pendingHyphen = false
        result.append(character)
      } else {
        pendingHyphen = true
      }
    }
    return result
  }

  /// Where a missing reference was looked for, for a failure message.
  var searchedDescription: String {
    if candidates.isEmpty {
      return
        "Looked for “\(fileName)” in the test bundle, because the source directory is not on this machine."
    }
    return "Looked at: " + candidates.map(\.path).joined(separator: ", ") + "."
  }
}
