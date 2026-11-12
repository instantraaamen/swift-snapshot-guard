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
import os

/// Why a snapshot test fails.
public struct SnapshotFailure: Error, Sendable, CustomStringConvertible {
  public enum Reason: Sendable, Equatable {
    /// There is no reference. `recorded` says whether this run wrote one.
    case missingReference(recorded: Bool)
    /// The snapshot matches a reference that this same process recorded earlier, so nothing
    /// was verified.
    case recordedOnly
    /// The reference was replaced because recording was set to ``SnapshotRecording/all``.
    case rerecorded
    /// The snapshot differs from its reference.
    case mismatch
    /// The snapshot was rejected without looking at the reference.
    case invalid
    /// The value could not be turned into a snapshot.
    case encodingFailed
  }

  public var reason: Reason
  public var message: String
  /// Files to attach to the test. Their names are built by ``SnapshotAttachment/name(kind:directory:fileName:)``.
  public var attachments: [SnapshotAttachment]
  /// The reference file name, such as `profile.Profile_en.png`.
  public var fileName: String
  /// The directory the reference belongs to, such as `ProfileSnapshotTests`.
  public var directoryName: String

  public var description: String { message }
}

/// Remembers which references this process wrote.
///
/// A recorded reference fails its test. If the test is retried in the same process, the retry
/// finds the file the first attempt wrote and would pass against it, turning a run that
/// verified nothing green.
final class RecordedReferences: Sendable {
  static let shared = RecordedReferences()

  private let paths = OSAllocatedUnfairLock(initialState: Set<String>())

  func insert(_ url: URL) {
    _ = paths.withLock { $0.insert(url.standardizedFileURL.path) }
  }

  func contains(_ url: URL) -> Bool {
    paths.withLock { $0.contains(url.standardizedFileURL.path) }
  }
}

/// The decision at the heart of a snapshot test, without the test framework around it.
struct SnapshotVerifier: Sendable {
  var configuration: SnapshotConfiguration
  var location: ReferenceLocation
  var recorded: RecordedReferences = .shared

  /// - Parameters:
  ///   - snapshotName: The name to use in messages.
  ///   - encode: Produces the snapshot of this run. Not called when only the existence of the
  ///     reference is checked.
  /// - Returns: `nil` when the test passes.
  @MainActor
  func verify(
    snapshotName: String,
    pathExtension: String,
    validate: (Data) -> String?,
    compare: (_ reference: Data, _ actual: Data) -> SnapshotMismatch?,
    encode: () async throws -> Data
  ) async -> SnapshotFailure? {
    func failure(
      _ reason: SnapshotFailure.Reason, _ message: String, _ attachments: [SnapshotAttachment] = []
    ) -> SnapshotFailure {
      SnapshotFailure(
        reason: reason, message: message, attachments: attachments, fileName: location.fileName,
        directoryName: location.directoryName)
    }

    let existing = location.candidates.first { FileManager.default.fileExists(atPath: $0.path) }

    if case .referenceExists = configuration.verification {
      guard let existing else {
        return failure(
          .missingReference(recorded: false),
          "No reference for “\(snapshotName)” exists. \(location.searchedDescription) "
            + "Record it where snapshots are compared, and commit it.")
      }
      return recorded.contains(existing) ? recordedOnlyFailure(snapshotName, failure) : nil
    }

    let actual: Data
    do {
      actual = try await encode()
    } catch {
      return failure(
        .encodingFailed, "“\(snapshotName)” could not be turned into a snapshot: \(error)")
    }
    if let reason = validate(actual) {
      return failure(
        .invalid, "“\(snapshotName)” was rejected: \(reason)",
        [SnapshotAttachment(kind: .actual, data: actual, pathExtension: pathExtension)])
    }

    guard let existing, configuration.recording != .all else {
      let attachment = SnapshotAttachment(
        kind: .recorded, data: actual, pathExtension: pathExtension)
      let wrote = configuration.recording != .never && write(actual)
      if existing != nil {
        return failure(
          .rerecorded,
          wrote
            ? "Recorded “\(snapshotName)” again because recording is set to `all`. Nothing was verified."
            : "Recording is set to `all`, but there is nowhere to write “\(snapshotName)” on this machine. "
              + "The snapshot is attached.",
          [attachment])
      }
      let how =
        wrote
        ? "This run recorded one at \(location.writable?.path ?? ""). Review it and commit it; the test "
          + "passes once the reference exists before the run starts."
        : "\(location.searchedDescription) The snapshot of this run is attached as “\(location.fileName)”; "
          + "review it and add it as the reference, for example with `snapshot-guard fetch`."
      return failure(
        .missingReference(recorded: wrote), "No reference for “\(snapshotName)” exists. \(how)",
        [attachment])
    }

    if recorded.contains(existing) {
      return recordedOnlyFailure(snapshotName, failure)
    }
    guard let reference = try? Data(contentsOf: existing) else {
      return failure(
        .mismatch, "The reference of “\(snapshotName)” at \(existing.path) could not be read.")
    }
    guard let mismatch = compare(reference, actual) else { return nil }
    return failure(
      .mismatch, "“\(snapshotName)” does not match its reference. \(mismatch.message)",
      mismatch.attachments)
  }

  private func recordedOnlyFailure(
    _ snapshotName: String,
    _ failure: (SnapshotFailure.Reason, String, [SnapshotAttachment]) -> SnapshotFailure
  ) -> SnapshotFailure {
    failure(
      .recordedOnly,
      "“\(snapshotName)” passed, but only against a reference that this same test run recorded earlier. "
        + "Nothing was verified. Review the recorded file and commit it.",
      [])
  }

  private func write(_ data: Data) -> Bool {
    guard let url = location.writable else { return false }
    do {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: url, options: .atomic)
      recorded.insert(url)
      return true
    } catch {
      return false
    }
  }
}
