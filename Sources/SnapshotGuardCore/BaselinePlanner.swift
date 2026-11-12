import Foundation

/// A recorded snapshot and the reference file it should become.
public struct BaselinePlacement: Equatable, Sendable {
  /// The suite the snapshot belongs to, used as the directory under `__Snapshots__`.
  public var suite: String
  /// The reference file name, such as `profile.ProfileView_en.png`.
  public var fileName: String
  /// The file name inside the export directory.
  public var exportedFileName: String
}

/// Turns the attachments of a test run into reference files.
///
/// When a reference is missing, swift-snapshot-testing records the image and attaches it to
/// the test as `<test function>.<name>_<counter>_<UUID>.png`. Stripping the suffix gives back
/// the reference file name.
public enum BaselinePlanner {
  /// The three images swift-snapshot-testing attaches when a comparison fails. They are not
  /// references, but stripping their suffix yields plausible names such as `failure.png`.
  static let mismatchAttachments: Set<String> = ["failure", "reference", "difference"]

  /// Picks the attachments that are newly recorded references.
  ///
  /// - Parameters:
  ///   - manifest: The decoded `manifest.json`.
  ///   - suiteSuffix: When set, only suites whose name ends with this text are considered.
  public static func plan(manifest: [ManifestEntry], suiteSuffix: String? = nil) -> [BaselinePlacement] {
    var placements: [BaselinePlacement] = []
    for entry in manifest {
      guard let suite = entry.testIdentifier.split(separator: "/").first.map(String.init) else {
        continue
      }
      if let suiteSuffix, !suite.hasSuffix(suiteSuffix) { continue }

      for attachment in entry.attachments {
        guard
          let name = attachment.suggestedHumanReadableName,
          let baseline = baselineName(fromAttachmentName: name)
        else { continue }
        // A retry compares against the image the first attempt wrote, so only the first
        // attempt holds what was actually recorded.
        guard (attachment.repetitionNumber ?? 1) == 1 else { continue }

        placements.append(
          BaselinePlacement(
            suite: suite,
            fileName: "\(baseline).png",
            exportedFileName: attachment.exportedFileName
          )
        )
      }
    }
    return placements
  }

  /// Returns the reference name for an attachment, or `nil` when the attachment is not a
  /// recorded reference.
  static func baselineName(fromAttachmentName name: String) -> String? {
    guard let suffix = name.range(of: #"_\d+_[0-9A-Fa-f-]{36}\.png$"#, options: .regularExpression)
    else { return nil }
    let baseline = String(name[..<suffix.lowerBound])
    if mismatchAttachments.contains(baseline) { return nil }
    // References are always `<test function>.<name>`. Anything else is of unknown origin.
    guard baseline.contains(".") else { return nil }
    return baseline
  }

  /// Copies the planned references into `snapshotsDirectory/<suite>/`.
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
      let directory = snapshotsDirectory.appendingPathComponent(placement.suite)
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
