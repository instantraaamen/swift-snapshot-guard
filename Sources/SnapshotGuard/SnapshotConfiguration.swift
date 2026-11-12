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
import Testing
import os

/// When a reference is written.
public enum SnapshotRecording: String, Sendable, CaseIterable {
  /// Never. A missing reference fails the test and the snapshot is attached to it.
  ///
  /// Use this on CI. Nothing is written next to the references, so a test that is retried
  /// cannot pass against a file that its own first attempt wrote.
  case never
  /// When there is none. The test fails, and passes on the next run.
  case missing
  /// Always, replacing what is there. The test fails, so that a recording run is never
  /// mistaken for a verification.
  case all

  /// The mode the `SNAPSHOT_GUARD_RECORD` environment variable asks for, or ``missing``.
  public static var fromEnvironment: SnapshotRecording {
    ProcessInfo.processInfo.environment["SNAPSHOT_GUARD_RECORD"].flatMap(SnapshotRecording.init)
      ?? .missing
  }
}

/// What a snapshot test checks.
public enum SnapshotVerification: Sendable {
  /// The snapshot is taken and compared with its reference.
  case comparison
  /// Only that a reference exists. Nothing is rendered.
  ///
  /// Images only compare equal in the environment that recorded them, so image suites are
  /// often skipped everywhere else. A skipped suite cannot notice that a reference was deleted
  /// and never recorded again. Running it in this mode on every machine can.
  case referenceExists
}

/// Where the references of a suite are kept.
public struct SnapshotDirectory: Equatable, Sendable {
  enum Storage: Equatable, Sendable {
    case nextToSourceFile(String)
    case fixed(URL)
  }

  var storage: Storage

  /// `__Snapshots__/<source file name>` next to the source file, which is the default.
  ///
  /// When the source file's directory does not exist where the tests run, the references are
  /// read from the test bundle instead. That is the case on CI services that build on one
  /// machine and test on another: copy the references into the test bundle as resources.
  public static func nextToSourceFile(_ filePath: StaticString = #filePath) -> SnapshotDirectory {
    SnapshotDirectory(storage: .nextToSourceFile("\(filePath)"))
  }

  /// A directory of your choice.
  public static func at(_ url: URL) -> SnapshotDirectory {
    SnapshotDirectory(storage: .fixed(url))
  }
}

/// The settings snapshot tests run with. Set them for a suite or a test with the
/// ``Testing/Trait/snapshots(recording:verifying:directory:imageTolerance:)`` trait.
public struct SnapshotConfiguration: Sendable {
  /// When references are written.
  public var recording: SnapshotRecording
  /// What is checked.
  public var verification: SnapshotVerification
  /// Where references are kept. `nil` means next to the file that takes the snapshot.
  public var directory: SnapshotDirectory?
  /// The tolerance of image strategies that do not set their own.
  public var imageTolerance: ImageTolerance

  /// Numbers unnamed snapshots within one run of a test.
  var counter: SnapshotCounter

  public init(
    recording: SnapshotRecording = .fromEnvironment,
    verification: SnapshotVerification = .comparison,
    directory: SnapshotDirectory? = nil,
    imageTolerance: ImageTolerance = .exact
  ) {
    self.recording = recording
    self.verification = verification
    self.directory = directory
    self.imageTolerance = imageTolerance
    self.counter = .processWide
  }

  /// The configuration of the test that is running.
  @TaskLocal public static var current = SnapshotConfiguration()
}

/// Numbers the unnamed snapshots of a test: 1, 2, 3.
final class SnapshotCounter: Sendable {
  /// Used when no trait scopes the counter to one run of a test. It never starts over, so a
  /// test that is run again in the same process continues counting.
  static let processWide = SnapshotCounter()

  private let counts = OSAllocatedUnfairLock(initialState: [String: Int]())

  func next(for key: String) -> Int {
    counts.withLock { counts in
      counts[key, default: 0] += 1
      return counts[key] ?? 1
    }
  }
}

/// Applies snapshot settings to a suite or a test.
public struct SnapshotsTrait: SuiteTrait, TestTrait, TestScoping {
  var update: @Sendable (inout SnapshotConfiguration) -> Void

  public var isRecursive: Bool { true }

  public func provideScope(
    for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void
  ) async throws {
    var configuration = SnapshotConfiguration.current
    update(&configuration)
    // A fresh counter for every run of a test, so that a retry numbers its snapshots from 1.
    configuration.counter = SnapshotCounter()
    try await SnapshotConfiguration.$current.withValue(configuration) {
      try await function()
    }
  }
}

extension Trait where Self == SnapshotsTrait {
  /// Sets how the snapshots of a suite or a test are recorded and verified.
  ///
  /// ```swift
  /// @Suite(.snapshots(recording: .never, imageTolerance: .pixels(0.002)))
  /// struct ScreenSnapshotTests { ... }
  /// ```
  ///
  /// A value that is left out keeps what an enclosing suite, or the default, says.
  ///
  /// - Parameters:
  ///   - recording: When references are written.
  ///   - verifying: What is checked.
  ///   - directory: Where references are kept.
  ///   - imageTolerance: The tolerance of image strategies that do not set their own.
  public static func snapshots(
    recording: SnapshotRecording? = nil,
    verifying: SnapshotVerification? = nil,
    directory: SnapshotDirectory? = nil,
    imageTolerance: ImageTolerance? = nil
  ) -> Self {
    SnapshotsTrait { configuration in
      if let recording { configuration.recording = recording }
      if let verifying { configuration.verification = verifying }
      if let directory { configuration.directory = directory }
      if let imageTolerance { configuration.imageTolerance = imageTolerance }
    }
  }
}
