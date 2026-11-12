import ArgumentParser
import Foundation
import SnapshotGuardCore

@main
struct SnapshotGuardCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "snapshot-guard",
    abstract: "Bring snapshot references recorded on CI back into your repository.",
    version: "0.1.0",
    subcommands: [Fetch.self, Check.self]
  )
}

struct Fetch: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Copy the snapshots a test run recorded into the __Snapshots__ directory.",
    discussion: """
      Delete the references you want to re-record, run the tests on CI, then run this command. \
      swift-snapshot-testing records a missing reference and attaches it to the test, and this \
      command puts each attachment back under its reference file name.

      Pass --xcresult to read a result bundle you already have, or --xcode-cloud to download \
      one from Xcode Cloud. Xcode Cloud needs an App Store Connect API key in \
      APP_STORE_CONNECT_API_KEY_KEY_ID, APP_STORE_CONNECT_API_KEY_ISSUER_ID and \
      APP_STORE_CONNECT_API_KEY_KEY_FILEPATH.
      """
  )

  @Option(name: .long, help: "The __Snapshots__ directory to write into.", completion: .directory)
  var snapshotsDir: String

  @Option(name: .long, help: "A result bundle on disk.", completion: .directory)
  var xcresult: String?

  @Flag(name: .long, help: "Download the result bundle from Xcode Cloud.")
  var xcodeCloud = false

  @Option(name: .long, help: "The Xcode Cloud product name. Defaults to every product.")
  var product: String?

  @Option(name: .long, help: "The Xcode Cloud workflow name. Defaults to any workflow.")
  var workflow: String?

  @Option(name: .long, help: "The Xcode Cloud build number. Defaults to the latest finished build.")
  var build: Int?

  @Option(name: .long, help: "Only take snapshots from suites whose name ends with this text.")
  var suiteSuffix: String?

  @Flag(name: .long, help: "List what would be written without writing it.")
  var dryRun = false

  func validate() throws {
    guard (xcresult != nil) != xcodeCloud else {
      throw ValidationError("Pass exactly one of --xcresult or --xcode-cloud.")
    }
  }

  func run() async throws {
    let workspace = FileManager.default.temporaryDirectory
      .appendingPathComponent("snapshot-guard-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: workspace) }

    let bundle: URL
    if let xcresult {
      bundle = URL(fileURLWithPath: xcresult)
    } else {
      let cloud = XcodeCloud(key: try .fromEnvironment())
      let archive = try await cloud.findResultArchive(.init(product: product, workflow: workflow, build: build))
      print("Build #\(archive.buildNumber): \(archive.fileName) (\(archive.fileSize / 1_048_576) MB)")
      let zip = workspace.appendingPathComponent("xcresult.zip")
      try await cloud.download(archive, to: zip)
      bundle = try XCResult.unzip(zip, to: workspace.appendingPathComponent("unzipped"))
    }

    let exportDirectory = workspace.appendingPathComponent("attachments")
    let manifest = try XCResult.exportAttachments(from: bundle, to: exportDirectory)
    let placements = BaselinePlanner.plan(manifest: manifest, suiteSuffix: suiteSuffix)
    let snapshots = URL(fileURLWithPath: snapshotsDir)

    if dryRun {
      for placement in placements {
        print("\(placement.suite)/\(placement.fileName)")
      }
      print("\(placements.count) snapshot(s) would be written to \(snapshots.path).")
      return
    }

    let written = try BaselinePlanner.place(placements, from: exportDirectory, into: snapshots)
    let audit = try BaselineAudit.audit(files: written)
    Report.printIdenticalFiles(audit.identicalFiles, relativeTo: snapshots)
    print("\(written.count) snapshot(s) written to \(snapshots.path).")
    print("Look at every image before you commit it.")
  }
}

struct Check: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Look for reference images that are probably wrong.",
    discussion: """
      Reports references with identical bytes, which usually means nothing was drawn, and \
      references in different suites that share a file name, which overwrite each other when \
      they are flattened into a test bundle.
      """
  )

  @Option(name: .long, help: "The __Snapshots__ directory to check.", completion: .directory)
  var snapshotsDir: String

  @Flag(name: .long, help: "Exit with a failure when anything is reported.")
  var strict = false

  func run() throws {
    let snapshots = URL(fileURLWithPath: snapshotsDir)
    let audit = try BaselineAudit.audit(directory: snapshots)
    Report.printIdenticalFiles(audit.identicalFiles, relativeTo: snapshots)
    Report.printNameCollisions(audit.nameCollisions, relativeTo: snapshots)
    if audit.isClean {
      print("No problems found.")
    } else if strict {
      throw ExitCode.failure
    }
  }
}

enum Report {
  static func printIdenticalFiles(_ groups: [[URL]], relativeTo root: URL) {
    for group in groups {
      print("warning: \(group.count) snapshots have identical bytes. Nothing may have been drawn:")
      for file in group { print("  \(relativePath(file, root))") }
    }
  }

  static func printNameCollisions(_ groups: [[URL]], relativeTo root: URL) {
    for group in groups {
      print("warning: \(group.count) snapshots share the file name \(group[0].lastPathComponent):")
      for file in group { print("  \(relativePath(file, root))") }
    }
  }

  private static func relativePath(_ file: URL, _ root: URL) -> String {
    let rootPath = root.standardizedFileURL.path + "/"
    let path = file.standardizedFileURL.path
    return path.hasPrefix(rootPath) ? String(path.dropFirst(rootPath.count)) : path
  }
}
