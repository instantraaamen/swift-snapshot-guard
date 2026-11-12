import Foundation

/// The result of a guarded snapshot comparison.
public enum GuardOutcome: Equatable, Sendable {
  /// The snapshot was compared against an existing reference and matched.
  case matched
  /// The comparison failed, or the reference was missing and has just been recorded.
  case failed(String)
  /// The comparison passed, but only against a reference this very process recorded earlier.
  case recordedOnly(String)
}

/// Remembers which snapshots were recorded, rather than compared, during this process.
///
/// swift-snapshot-testing writes the reference to disk when it is missing and fails the test.
/// If the test is retried in the same process (for example with a test plan that uses
/// "Retry on Failure"), the retry compares the snapshot against the file the first attempt
/// wrote, and passes. The registry keeps that from turning the run green.
final class RecordedOnlyRegistry: @unchecked Sendable {
  static let shared = RecordedOnlyRegistry()

  private let lock = NSLock()
  private var recorded: Set<String> = []

  func resolve(failure: String?, key: String) -> GuardOutcome {
    lock.lock()
    defer { lock.unlock() }

    if let failure {
      if failure.contains(SnapshotGuard.missingReferenceMarker) {
        recorded.insert(key)
      }
      return .failed(failure)
    }
    if recorded.contains(key) {
      return .recordedOnly(
        """
        The snapshot passed, but only against a reference that was recorded earlier in this \
        test run. Nothing was compared. Review the recorded image and commit it as the reference.
        """
      )
    }
    return .matched
  }
}
