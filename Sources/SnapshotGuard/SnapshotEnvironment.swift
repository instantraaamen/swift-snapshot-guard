import Foundation
import Testing

/// Decides whether snapshot tests can produce a meaningful comparison where they are running.
///
/// References only match the environment that recorded them. A different OS version changes
/// font rendering, and even the same simulator build can rasterize text differently on a CI
/// machine and on a developer machine. Pick one environment as the source of truth, and skip
/// the snapshot suites everywhere else:
///
/// ```swift
/// let snapshots = SnapshotEnvironment(baselineOSVersion: "18.2", policy: .ciOnly)
///
/// @Suite(.enabled(if: snapshots.shouldRun, snapshots.skipReason))
/// struct ScreenSnapshotTests { ... }
/// ```
public struct SnapshotEnvironment: Sendable {
  /// Where snapshot tests are allowed to run.
  public enum Policy: Sendable {
    /// Run on the baseline OS, on any machine.
    case baselineOSOnly
    /// Run on the baseline OS, and only where the repository checkout is not visible.
    ///
    /// This matches CI services that build on one machine and test on another, such as
    /// Xcode Cloud: the test machine has no checkout, so the source file this value was
    /// created in does not exist there.
    case ciOnly
  }

  /// The OS version the references were recorded on, such as `"18.2"` or `"18"`.
  public let baselineOSVersion: String
  /// Where snapshot tests are allowed to run.
  public let policy: Policy

  let sourceDirectory: String
  let currentOSVersion: String
  let fileExists: @Sendable (String) -> Bool

  /// Creates an environment.
  ///
  /// - Parameters:
  ///   - baselineOSVersion: The OS version the references were recorded on. A shorter version
  ///     matches every release below it: `"18"` matches 18.0 and 18.2.1.
  ///   - policy: Where snapshot tests are allowed to run.
  ///   - filePath: A source file inside the repository. Leave the default so that it points at
  ///     the file that creates the environment.
  public init(
    baselineOSVersion: String,
    policy: Policy = .baselineOSOnly,
    filePath: StaticString = #filePath
  ) {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    self.init(
      baselineOSVersion: baselineOSVersion,
      policy: policy,
      sourceDirectory: URL(fileURLWithPath: "\(filePath)").deletingLastPathComponent().path,
      currentOSVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
      fileExists: { FileManager.default.fileExists(atPath: $0) }
    )
  }

  init(
    baselineOSVersion: String,
    policy: Policy,
    sourceDirectory: String,
    currentOSVersion: String,
    fileExists: @escaping @Sendable (String) -> Bool
  ) {
    self.baselineOSVersion = baselineOSVersion
    self.policy = policy
    self.sourceDirectory = sourceDirectory
    self.currentOSVersion = currentOSVersion
    self.fileExists = fileExists
  }

  /// Whether the tests are running on the OS version the references were recorded on.
  public var isBaselineOS: Bool {
    let baseline = baselineOSVersion.split(separator: ".")
    let current = currentOSVersion.split(separator: ".")
    return baseline.count <= current.count && zip(baseline, current).allSatisfy(==)
  }

  /// Whether the repository checkout is visible, which means the tests are running on a
  /// developer machine or on a CI machine that tests where it builds.
  public var hasRepositoryCheckout: Bool {
    fileExists(sourceDirectory)
  }

  /// Whether snapshot tests should run here.
  public var shouldRun: Bool {
    switch policy {
    case .baselineOSOnly:
      return isBaselineOS
    case .ciOnly:
      return isBaselineOS && !hasRepositoryCheckout
    }
  }

  /// The reason to show when the snapshot suites are skipped.
  public var skipReason: Comment {
    switch policy {
    case .baselineOSOnly:
      return Comment(
        rawValue: "Snapshot tests only run on OS \(baselineOSVersion), where the references were recorded."
      )
    case .ciOnly:
      return Comment(
        rawValue: "Snapshot tests only run on CI with OS \(baselineOSVersion), where the references were recorded."
      )
    }
  }
}
