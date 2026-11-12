import Foundation

/// Finds the directory that holds the references for a suite.
public enum SnapshotDirectory {
  /// Returns `__Snapshots__/<suite>` next to the calling source file, or the test bundle when
  /// that directory does not exist.
  ///
  /// CI services that build on one machine and test on another, such as Xcode Cloud, have no
  /// repository checkout on the test machine, so the path derived from `#filePath` is missing
  /// there. If the references are copied into the test bundle as resources, they can be read
  /// from the bundle instead.
  ///
  /// Resources are usually flattened into the bundle root, so reference file names must be
  /// unique across suites. `snapshot-guard check` reports collisions.
  ///
  /// - Parameters:
  ///   - suite: The directory name under `__Snapshots__`. swift-snapshot-testing uses the name
  ///     of the test file without its extension.
  ///   - bundle: The test bundle, for example `Bundle(for: SomeTestClass.self)`.
  ///   - filePath: A source file next to `__Snapshots__`. Leave the default.
  public static func resolve(
    suite: String,
    fallback bundle: Bundle,
    filePath: StaticString = #filePath
  ) -> String {
    resolve(
      suite: suite,
      fallbackPath: bundle.bundlePath,
      filePath: "\(filePath)",
      fileExists: { FileManager.default.fileExists(atPath: $0) }
    )
  }

  static func resolve(
    suite: String,
    fallbackPath: String,
    filePath: String,
    fileExists: (String) -> Bool
  ) -> String {
    let repository = URL(fileURLWithPath: filePath)
      .deletingLastPathComponent()
      .appendingPathComponent("__Snapshots__")
      .appendingPathComponent(suite)
      .path
    return fileExists(repository) ? repository : fallbackPath
  }
}
