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

import ArgumentParser
import Foundation
import SnapshotGuardTools
import SnapshotGuardXcodeCloud

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
      A snapshot test that has no reference fails and attaches its snapshot to the test. This \
      command reads those attachments from a result bundle and puts each one where its \
      reference belongs. With --include-mismatched it also takes the snapshots that did not \
      match, which adopts an intended change without deleting anything first.

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

  @Option(name: .long, help: "Only take snapshots whose directory name ends with this text.")
  var directorySuffix: String?

  @Flag(name: .long, help: "Also take the snapshots that did not match their reference.")
  var includeMismatched = false

  @Flag(name: .long, help: "List the attachments that are left out, with the reason.")
  var verbose = false

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
      let archive = try await cloud.findResultArchive(
        .init(product: product, workflow: workflow, build: build))
      print(
        "Build #\(archive.buildNumber): \(archive.fileName) (\(archive.fileSize / 1_048_576) MB)")
      let zip = workspace.appendingPathComponent("xcresult.zip")
      try await cloud.download(archive, to: zip)
      bundle = try XCResult.unzip(zip, to: workspace.appendingPathComponent("unzipped"))
    }

    let exportDirectory = workspace.appendingPathComponent("attachments")
    let manifest = try XCResult.exportAttachments(from: bundle, to: exportDirectory)
    let plan = BaselinePlanner.plan(
      manifest: manifest, includeMismatched: includeMismatched, directorySuffix: directorySuffix)
    let placements = plan.placements
    let snapshots = URL(fileURLWithPath: snapshotsDir)

    if verbose {
      for skipped in plan.skipped {
        print("left out: \(skipped.name) (\(skipped.reason))")
      }
    }
    let mismatched = plan.skipped.filter { $0.reason.hasPrefix("did not match") }.count
    if mismatched > 0 {
      print(
        "\(mismatched) snapshot(s) did not match their reference. Pass --include-mismatched to adopt them."
      )
    }
    if dryRun {
      for placement in placements {
        print("\(placement.directory)/\(placement.fileName) (\(placement.kind.rawValue))")
      }
      print("\(placements.count) snapshot(s) would be written to \(snapshots.path).")
      return
    }

    let written = try BaselinePlanner.place(placements, from: exportDirectory, into: snapshots)
    let audit = try BaselineAudit.audit(files: written)
    Report.printIdenticalFiles(audit.identicalFiles, relativeTo: snapshots)
    Report.printUniformImages(audit.uniformImages, relativeTo: snapshots)
    print("\(written.count) snapshot(s) written to \(snapshots.path).")
    print("Look at every image before you commit it.")
  }
}

struct Check: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Look for reference images that are probably wrong.",
    discussion: """
      Reports references with identical bytes and references of one flat colour, which usually \
      mean nothing was drawn; references in different directories that share a file name, which \
      overwrite each other when they are flattened into a test bundle; and references that were \
      recorded in more than one environment, which cannot all match one test run.
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
    Report.printUniformImages(audit.uniformImages, relativeTo: snapshots)
    Report.printEnvironments(audit.environments, relativeTo: snapshots)
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

  static func printUniformImages(_ files: [URL], relativeTo root: URL) {
    guard !files.isEmpty else { return }
    print("warning: \(files.count) snapshot(s) are one flat colour. Nothing may have been drawn:")
    for file in files { print("  \(relativePath(file, root))") }
  }

  static func printEnvironments(_ environments: [String: [URL]], relativeTo root: URL) {
    guard !environments.isEmpty else { return }
    print("warning: the snapshots were recorded in \(environments.count) different environments:")
    for (environment, files) in environments.sorted(by: { $0.value.count > $1.value.count }) {
      print("  \(environment): \(files.count) file(s), such as \(relativePath(files[0], root))")
    }
  }

  private static func relativePath(_ file: URL, _ root: URL) -> String {
    let rootPath = root.standardizedFileURL.path + "/"
    let path = file.standardizedFileURL.path
    return path.hasPrefix(rootPath) ? String(path.dropFirst(rootPath.count)) : path
  }
}
