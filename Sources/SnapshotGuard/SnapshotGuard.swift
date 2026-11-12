import Foundation
import SnapshotTesting
import Testing

/// Namespace for values shared by the guarded snapshot functions.
public enum SnapshotGuard {
  /// The text swift-snapshot-testing puts in its failure message when a reference is missing
  /// and has just been recorded.
  ///
  /// The guard reads the library's own verdict instead of rebuilding the reference file name,
  /// because the naming rules are private to the library. The price is a dependency on this
  /// wording; call ``missingReferenceCheck()`` from one of your tests to notice if it changes.
  public static let missingReferenceMarker = "No reference was found on disk"

  /// Checks that swift-snapshot-testing still reports a missing reference with the wording
  /// the guard looks for.
  ///
  /// Add one test that calls this, so that a library upgrade that changes the wording fails
  /// loudly instead of silently disabling the guard:
  ///
  /// ```swift
  /// @Test func snapshotGuardIsAlive() {
  ///   #expect(SnapshotGuard.missingReferenceCheck() == nil)
  /// }
  /// ```
  ///
  /// - Returns: `nil` when the guard works, otherwise a description of what went wrong.
  public static func missingReferenceCheck() -> String? {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("snapshot-guard-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }

    let failure = verifySnapshot(
      of: "snapshot-guard",
      as: .lines,
      named: "missing-reference",
      snapshotDirectory: directory.path,
      testName: "missingReferenceCheck"
    )
    guard let failure else {
      return "swift-snapshot-testing did not fail when the reference was missing."
    }
    guard failure.contains(missingReferenceMarker) else {
      return """
        swift-snapshot-testing changed its missing-reference message, so the guard can no \
        longer detect recorded-only snapshots. Actual message: \(failure)
        """
    }
    return nil
  }
}

/// Compares a value against its reference and returns a failure message, like `verifySnapshot`,
/// but also fails when the reference was only recorded earlier in the same test run.
///
/// The parameters mirror `verifySnapshot` in swift-snapshot-testing. To control recording, wrap
/// the call in `withSnapshotTesting(record:)`.
///
/// - Returns: `nil` when the snapshot matched a pre-existing reference, otherwise a failure
///   message.
public func verifyGuardedSnapshot<Value, Format>(
  of value: @autoclosure () throws -> Value,
  as snapshotting: Snapshotting<Value, Format>,
  named name: String? = nil,
  snapshotDirectory: String? = nil,
  timeout: TimeInterval = 5,
  fileID: StaticString = #fileID,
  file filePath: StaticString = #filePath,
  testName: String = #function,
  line: UInt = #line,
  column: UInt = #column
) -> String? {
  let failure = verifySnapshot(
    of: try value(),
    as: snapshotting,
    named: name,
    snapshotDirectory: snapshotDirectory,
    timeout: timeout,
    fileID: fileID,
    file: filePath,
    testName: testName,
    line: line,
    column: column
  )
  let key = "\(snapshotDirectory ?? "\(filePath)")|\(testName)|\(name ?? "")"
  switch RecordedOnlyRegistry.shared.resolve(failure: failure, key: key) {
  case .matched:
    return nil
  case .failed(let message), .recordedOnly(let message):
    return message
  }
}

/// Asserts that a value matches its reference, like `assertSnapshot`, but also fails when the
/// reference was only recorded earlier in the same test run.
///
/// Failures are reported to Swift Testing. From XCTest, call ``verifyGuardedSnapshot(of:as:named:snapshotDirectory:timeout:fileID:file:testName:line:column:)``
/// and pass the result to `XCTFail`.
public func assertGuardedSnapshot<Value, Format>(
  of value: @autoclosure () throws -> Value,
  as snapshotting: Snapshotting<Value, Format>,
  named name: String? = nil,
  snapshotDirectory: String? = nil,
  timeout: TimeInterval = 5,
  fileID: StaticString = #fileID,
  file filePath: StaticString = #filePath,
  testName: String = #function,
  line: UInt = #line,
  column: UInt = #column
) {
  let failure = verifyGuardedSnapshot(
    of: try value(),
    as: snapshotting,
    named: name,
    snapshotDirectory: snapshotDirectory,
    timeout: timeout,
    fileID: fileID,
    file: filePath,
    testName: testName,
    line: line,
    column: column
  )
  guard let failure else { return }
  Issue.record(
    Comment(rawValue: failure),
    sourceLocation: SourceLocation(
      fileID: "\(fileID)",
      filePath: "\(filePath)",
      line: Int(line),
      column: Int(column)
    )
  )
}
