import CryptoKit
import Foundation

/// Problems found in a set of reference images.
public struct BaselineAudit: Equatable, Sendable {
  /// Groups of files with identical bytes. Two different screens that produce the same image
  /// usually means nothing was drawn.
  public var identicalFiles: [[URL]]
  /// Groups of files in different suites that share a file name. They overwrite each other
  /// when references are flattened into a test bundle.
  public var nameCollisions: [[URL]]

  public var isClean: Bool { identicalFiles.isEmpty && nameCollisions.isEmpty }

  /// Audits the given reference images.
  public static func audit(files: [URL]) throws -> BaselineAudit {
    var byDigest: [String: [URL]] = [:]
    var byName: [String: [URL]] = [:]
    for file in files {
      let digest = SHA256.hash(data: try Data(contentsOf: file))
        .map { String(format: "%02x", $0) }
        .joined()
      byDigest[digest, default: []].append(file)
      byName[file.lastPathComponent, default: []].append(file)
    }
    return BaselineAudit(
      identicalFiles: groups(in: byDigest),
      nameCollisions: groups(in: byName)
    )
  }

  /// Audits every PNG under `directory`.
  public static func audit(directory: URL) throws -> BaselineAudit {
    try audit(files: pngFiles(under: directory))
  }

  static func pngFiles(under directory: URL) -> [URL] {
    guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
    else { return [] }
    return enumerator
      .compactMap { $0 as? URL }
      .filter { $0.pathExtension.lowercased() == "png" }
      .sorted { $0.path < $1.path }
  }

  private static func groups(in table: [String: [URL]]) -> [[URL]] {
    table.values
      .filter { $0.count > 1 }
      .map { $0.sorted { $0.path < $1.path } }
      .sorted { ($0.count, $1[0].path) > ($1.count, $0[0].path) }
  }
}
