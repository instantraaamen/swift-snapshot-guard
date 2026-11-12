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

@testable import SnapshotGuardTools

@Suite struct BaselinePlannerTests {
  private let uuid = "0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0"

  private func entry(
    _ identifier: String,
    _ names: [String],
    repetition: Int? = nil
  ) -> ManifestEntry {
    ManifestEntry(
      testIdentifier: identifier,
      attachments: names.enumerated().map { index, name in
        .init(
          exportedFileName: "\(identifier)-\(repetition ?? 1)-\(index).png",
          suggestedHumanReadableName: name,
          repetitionNumber: repetition
        )
      }
    )
  }

  @Test func readsTheKindTheDirectoryAndTheFileName() throws {
    let parsed = try #require(
      BaselinePlanner.parse(
        attachmentName: "recorded~ProfileTests~profile.Profile_en_0_\(uuid).png"))
    #expect(parsed.kind == "recorded")
    #expect(parsed.directory == "ProfileTests")
    #expect(parsed.fileName == "profile.Profile_en.png")

    // Without the counter and the UUID, as the library names it.
    #expect(
      BaselinePlanner.parse(attachmentName: "actual~ProfileTests~profile.1.txt")?.fileName
        == "profile.1.txt")
  }

  @Test func leavesOtherAttachmentsAlone() {
    #expect(BaselinePlanner.parse(attachmentName: "Screenshot_0_\(uuid).png") == nil)
    #expect(BaselinePlanner.parse(attachmentName: "recorded~~profile.png") == nil)
    // A name must not be able to place a file outside the snapshots directory.
    #expect(BaselinePlanner.parse(attachmentName: "recorded~..~profile.png") == nil)
    #expect(BaselinePlanner.parse(attachmentName: "recorded~Tests~../../profile.png") == nil)
  }

  @Test func takesRecordedSnapshotsAndSaysWhyTheRestIsLeftOut() {
    let plan = BaselinePlanner.plan(manifest: [
      entry(
        "ProfileTests/profile()",
        [
          "recorded~ProfileTests~profile.Profile_en_0_\(uuid).png",
          "recorded~ProfileTests~profile.Profile_ja_1_\(uuid).png",
        ]),
      entry(
        "SettingsTests/settings()",
        [
          "actual~SettingsTests~settings.Settings_0_\(uuid).png",
          "reference~SettingsTests~settings.Settings_1_\(uuid).png",
          "difference~SettingsTests~settings.Settings_2_\(uuid).png",
          "Screenshot_3_\(uuid).png",
        ]),
    ])
    #expect(
      plan.placements.map(\.fileName) == ["profile.Profile_en.png", "profile.Profile_ja.png"])
    #expect(plan.placements.map(\.directory) == ["ProfileTests", "ProfileTests"])
    #expect(plan.placements.allSatisfy { $0.kind == .recorded })
    #expect(
      plan.skipped.map(\.reason) == [
        "did not match its reference; pass --include-mismatched to adopt it",
        "only there to look at (reference)",
        "only there to look at (difference)",
        "not a snapshot attachment",
      ])
  }

  /// After an intended change every screen fails. Adopting the new images used to mean
  /// deleting the references first and running the tests once more, and a reference that was
  /// deleted and then forgotten went missing for weeks.
  @Test func canAdoptSnapshotsThatDidNotMatch() {
    let plan = BaselinePlanner.plan(
      manifest: [
        entry(
          "SettingsTests/settings()",
          [
            "actual~SettingsTests~settings.Settings_0_\(uuid).png",
            "reference~SettingsTests~settings.Settings_1_\(uuid).png",
          ])
      ],
      includeMismatched: true)
    #expect(plan.placements.map(\.kind) == [.actual])
    #expect(plan.placements.map(\.fileName) == ["settings.Settings.png"])
  }

  /// The directory comes from the attachment, not from the test identifier: a helper in
  /// another suite or a renamed suite must not send a reference to the wrong place.
  @Test func theDirectoryComesFromTheAttachment() {
    let plan = BaselinePlanner.plan(manifest: [
      entry("SomeOtherSuite/helper()", ["recorded~ProfileTests~profile.Profile_0_\(uuid).png"])
    ])
    #expect(plan.placements.map(\.directory) == ["ProfileTests"])
  }

  @Test func takesARetriedSnapshotOnce() {
    let name = "recorded~ProfileTests~profile.Profile_0_\(uuid).png"
    let plan = BaselinePlanner.plan(manifest: [
      entry("ProfileTests/profile()", [name], repetition: 1),
      entry("ProfileTests/profile()", [name], repetition: 2),
    ])
    #expect(plan.placements.map(\.exportedFileName) == ["ProfileTests/profile()-1-0.png"])
    #expect(plan.skipped.map(\.reason) == ["already taken from an earlier attempt"])
  }

  @Test func filtersByDirectorySuffix() {
    let plan = BaselinePlanner.plan(
      manifest: [
        entry("A/a()", ["recorded~ProfileSnapshotTests~a.A_0_\(uuid).png"]),
        entry("B/b()", ["recorded~FormatterTests~b.B_0_\(uuid).txt"]),
      ],
      directorySuffix: "SnapshotTests")
    #expect(plan.placements.map(\.directory) == ["ProfileSnapshotTests"])
  }

  @Test func decodesManifestWithoutAttachments() throws {
    let json = #"[{"testIdentifier": "ProfileTests/profile()"}]"#
    let manifest = try JSONDecoder().decode([ManifestEntry].self, from: Data(json.utf8))
    #expect(manifest == [ManifestEntry(testIdentifier: "ProfileTests/profile()", attachments: [])])
  }

  @Test func placesFilesUnderTheirDirectories() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let export = root.appendingPathComponent("export")
    let snapshots = root.appendingPathComponent("__Snapshots__")
    try FileManager.default.createDirectory(at: export, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("new".utf8).write(to: export.appendingPathComponent("exported.png"))
    // An existing reference is replaced.
    let existing = snapshots.appendingPathComponent("ProfileTests/profile.Profile.png")
    try FileManager.default.createDirectory(
      at: existing.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("old".utf8).write(to: existing)

    let written = try BaselinePlanner.place(
      [
        .init(
          kind: .recorded, directory: "ProfileTests", fileName: "profile.Profile.png",
          exportedFileName: "exported.png")
      ],
      from: export, into: snapshots)
    #expect(written == [existing])
    #expect(try Data(contentsOf: existing) == Data("new".utf8))
  }
}
