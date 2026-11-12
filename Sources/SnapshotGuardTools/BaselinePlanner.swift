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

/// A snapshot from a test run and the reference file it should become.
public struct BaselinePlacement: Equatable, Sendable {
  /// What the attachment is: a snapshot that had no reference, or one that did not match its
  /// reference.
  public enum Kind: String, Sendable {
    case recorded
    case actual
  }

  public var kind: Kind
  /// The directory under `__Snapshots__` the reference belongs to.
  public var directory: String
  /// The reference file name, such as `profile.Profile_en.png`.
  public var fileName: String
  /// The file name inside the export directory.
  public var exportedFileName: String
}

/// What `snapshot-guard fetch` would do with the attachments of a test run.
public struct BaselinePlan: Equatable, Sendable {
  /// An attachment that is left where it is, and why.
  public struct Skipped: Equatable, Sendable {
    public var name: String
    public var reason: String
  }

  public var placements: [BaselinePlacement]
  public var skipped: [Skipped]
}

/// Turns the attachments of a test run into reference files.
///
/// swift-snapshot-guard attaches every snapshot that fails under the name
/// `<kind>~<directory>~<reference file name>`. The kind says what the file is, so nothing has
/// to be guessed from what a name looks like.
public enum BaselinePlanner {
  /// Decides which attachments become references.
  ///
  /// - Parameters:
  ///   - manifest: The decoded `manifest.json`.
  ///   - includeMismatched: Also take the snapshots that did not match their reference. Use it
  ///     after an intended change, to adopt what the screens look like now.
  ///   - directorySuffix: When set, only directories whose name ends with this text are
  ///     considered.
  public static func plan(
    manifest: [ManifestEntry], includeMismatched: Bool = false, directorySuffix: String? = nil
  ) -> BaselinePlan {
    var placements: [BaselinePlacement] = []
    var skipped: [BaselinePlan.Skipped] = []
    var taken = Set<String>()

    for entry in manifest {
      for attachment in entry.attachments {
        guard let name = attachment.suggestedHumanReadableName else { continue }
        func skip(_ reason: String) {
          skipped.append(.init(name: name, reason: reason))
        }
        guard let parsed = parse(attachmentName: name) else {
          skip("not a snapshot attachment")
          continue
        }
        let kind: BaselinePlacement.Kind
        switch parsed.kind {
        case "recorded":
          kind = .recorded
        case "actual":
          guard includeMismatched else {
            skip("did not match its reference; pass --include-mismatched to adopt it")
            continue
          }
          kind = .actual
        default:
          skip("only there to look at (\(parsed.kind))")
          continue
        }
        if let directorySuffix, !parsed.directory.hasSuffix(directorySuffix) {
          skip("its directory does not end with \(directorySuffix)")
          continue
        }
        // A retried test attaches its snapshot again. Every attempt produced it the same way,
        // so the first one is as good as any.
        guard taken.insert("\(parsed.directory)/\(parsed.fileName)").inserted else {
          skip("already taken from an earlier attempt")
          continue
        }
        placements.append(
          BaselinePlacement(
            kind: kind, directory: parsed.directory, fileName: parsed.fileName,
            exportedFileName: attachment.exportedFileName))
      }
    }
    return BaselinePlan(placements: placements, skipped: skipped)
  }

  /// Splits an attachment name as exported by `xcresulttool` into its parts.
  ///
  /// The tool inserts a counter and a UUID before the extension:
  /// `recorded~ProfileTests~profile.Profile_en_0_<UUID>.png`.
  static func parse(attachmentName name: String) -> (
    kind: String, directory: String, fileName: String
  )? {
    let parts = name.components(separatedBy: "~")
    guard parts.count == 3, !parts[0].isEmpty, !parts[1].isEmpty, !parts[2].isEmpty else {
      return nil
    }
    // Neither part may leave the directory it is placed in.
    guard !parts[1].contains("/"), !parts[2].contains("/"), parts[1] != "..", parts[2] != ".."
    else { return nil }
    var fileName = parts[2]
    if let suffix = fileName.range(
      of: #"_\d+_[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}(?=(\.[A-Za-z0-9]+)?$)"#,
      options: .regularExpression)
    {
      fileName.removeSubrange(suffix)
    }
    return (parts[0], parts[1], fileName)
  }

  /// Copies the planned references into `snapshotsDirectory/<directory>/`.
  ///
  /// - Returns: The files that were written.
  @discardableResult
  public static func place(
    _ placements: [BaselinePlacement],
    from exportDirectory: URL,
    into snapshotsDirectory: URL
  ) throws -> [URL] {
    let fileManager = FileManager.default
    var written: [URL] = []
    for placement in placements {
      let directory = snapshotsDirectory.appendingPathComponent(placement.directory)
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
      let destination = directory.appendingPathComponent(placement.fileName)
      if fileManager.fileExists(atPath: destination.path) {
        try fileManager.removeItem(at: destination)
      }
      try fileManager.copyItem(
        at: exportDirectory.appendingPathComponent(placement.exportedFileName),
        to: destination
      )
      written.append(destination)
    }
    return written
  }
}
