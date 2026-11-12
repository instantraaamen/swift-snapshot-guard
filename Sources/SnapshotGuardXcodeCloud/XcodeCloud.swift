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

/// Finds and downloads the result bundle of an Xcode Cloud test run.
public struct XcodeCloud: Sendable {
  /// A result bundle archive attached to a build.
  public struct ResultArchive: Equatable, Sendable {
    public var buildNumber: Int
    public var fileName: String
    public var fileSize: Int
    public var downloadURL: URL
  }

  /// Which build to read.
  public struct Query: Sendable {
    /// The Xcode Cloud product name. `nil` searches every product.
    public var product: String?
    /// The workflow name. `nil` accepts any workflow.
    public var workflow: String?
    /// The build number. `nil` picks the latest build that has finished.
    public var build: Int?

    public init(product: String? = nil, workflow: String? = nil, build: Int? = nil) {
      self.product = product
      self.workflow = workflow
      self.build = build
    }
  }

  let client: AppStoreConnectClient

  public init(key: AppStoreConnectKey) {
    client = AppStoreConnectClient(key: key)
  }

  /// Finds the archive that holds the result bundle of the test action.
  public func findResultArchive(_ query: Query) async throws -> ResultArchive {
    var products = try await client.all("ciProducts")
    if let name = query.product {
      products = products.filter { $0.attributes?.name == name }
      guard !products.isEmpty else {
        throw AppStoreConnectError.notFound("No Xcode Cloud product is named \"\(name)\".")
      }
    }

    var sources: [String] = []
    if let name = query.workflow {
      for product in products {
        let workflows = try await client.all("ciProducts/\(product.id)/workflows")
        sources += workflows.filter { $0.attributes?.name == name }.map {
          "ciWorkflows/\($0.id)/buildRuns"
        }
      }
      guard !sources.isEmpty else {
        throw AppStoreConnectError.notFound("No Xcode Cloud workflow is named \"\(name)\".")
      }
    } else {
      sources = products.map { "ciProducts/\($0.id)/buildRuns" }
    }

    // Take the newest matching run across every source. A run that is still in progress has
    // no artifacts yet, so it is skipped unless it was asked for by number.
    var best: (id: String, number: Int)?
    for source in sources {
      let found = try await client.firstMatch(source, query: ["sort": "-number", "limit": "50"]) {
        run -> (id: String, number: Int)? in
        guard let number = run.attributes?.number else { return nil }
        if let wanted = query.build {
          return number == wanted ? (run.id, number) : nil
        }
        return run.attributes?.executionProgress == "COMPLETE" ? (run.id, number) : nil
      }
      if let found, found.number > (best?.number ?? .min) { best = found }
    }
    guard let run = best else {
      throw AppStoreConnectError.notFound(
        query.build.map { "Build #\($0) was not found." } ?? "No finished build was found."
      )
    }

    var candidates: [ResultArchive] = []
    for action in try await client.all("ciBuildRuns/\(run.id)/actions") {
      for artifact in try await client.all("ciBuildActions/\(action.id)/artifacts") {
        guard
          let attributes = artifact.attributes,
          let fileName = attributes.fileName,
          let downloadURL = attributes.downloadUrl,
          Self.isTestResultArchive(fileName)
        else { continue }
        candidates.append(
          ResultArchive(
            buildNumber: run.number,
            fileName: fileName,
            fileSize: attributes.fileSize ?? 0,
            downloadURL: downloadURL
          )
        )
      }
    }
    // Several archives can remain (one per test plan or destination). The one that carries
    // attachments is by far the largest.
    guard let archive = candidates.max(by: { $0.fileSize < $1.fileSize }) else {
      throw AppStoreConnectError.notFound(
        "Build #\(run.number) has no test result bundle. The build may not have reached the test action."
      )
    }
    return archive
  }

  /// Whether an artifact is the result bundle of a test run.
  ///
  /// The build-for-testing action also uploads a result bundle, but it holds no attachments.
  static func isTestResultArchive(_ fileName: String) -> Bool {
    fileName.hasSuffix(".zip") && fileName.contains("XCResult")
      && !fileName.contains("build-for-testing")
  }

  /// Downloads the archive to `destination`.
  public func download(_ archive: ResultArchive, to destination: URL) async throws {
    let (temporary, response) = try await URLSession.shared.download(from: archive.downloadURL)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status) else {
      throw AppStoreConnectError.http(status: status, url: archive.downloadURL, body: "")
    }
    if FileManager.default.fileExists(atPath: destination.path) {
      try FileManager.default.removeItem(at: destination)
    }
    try FileManager.default.moveItem(at: temporary, to: destination)
  }
}
