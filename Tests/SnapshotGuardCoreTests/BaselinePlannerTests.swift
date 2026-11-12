import Foundation
import Testing

@testable import SnapshotGuardCore

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
          exportedFileName: "\(identifier.hashValue)-\(index).png",
          suggestedHumanReadableName: name,
          repetitionNumber: repetition
        )
      }
    )
  }

  @Test func stripsCounterAndUUID() {
    let name = BaselinePlanner.baselineName(
      fromAttachmentName: "profile.ProfileView_en_0_\(uuid).png"
    )
    #expect(name == "profile.ProfileView_en")
  }

  @Test func ignoresMismatchImages() {
    for name in ["failure", "reference", "difference"] {
      #expect(BaselinePlanner.baselineName(fromAttachmentName: "\(name)_0_\(uuid).png") == nil)
    }
  }

  @Test func ignoresAttachmentsThatAreNotSnapshots() {
    #expect(BaselinePlanner.baselineName(fromAttachmentName: "Launch Screen_0_\(uuid).png") == nil)
    #expect(BaselinePlanner.baselineName(fromAttachmentName: "failure description.txt") == nil)
  }

  @Test func plansOnePlacementPerRecordedSnapshot() {
    let manifest = [
      entry("ScreenSnapshotTests/profile()", [
        "profile.Profile_en_0_\(uuid).png",
        "profile.Profile_ja_1_\(uuid).png",
      ])
    ]
    let placements = BaselinePlanner.plan(manifest: manifest)
    #expect(placements.map(\.suite) == ["ScreenSnapshotTests", "ScreenSnapshotTests"])
    #expect(placements.map(\.fileName) == ["profile.Profile_en.png", "profile.Profile_ja.png"])
  }

  @Test func skipsRetries() {
    let manifest = [
      entry("ScreenSnapshotTests/profile()", ["profile.Profile_0_\(uuid).png"], repetition: 2)
    ]
    #expect(BaselinePlanner.plan(manifest: manifest).isEmpty)
  }

  @Test func filtersBySuiteSuffix() {
    let manifest = [
      entry("ScreenSnapshotTests/a()", ["a.A_0_\(uuid).png"]),
      entry("LoginUITests/b()", ["b.B_0_\(uuid).png"]),
    ]
    let placements = BaselinePlanner.plan(manifest: manifest, suiteSuffix: "SnapshotTests")
    #expect(placements.map(\.suite) == ["ScreenSnapshotTests"])
  }

  @Test func decodesManifestWithoutAttachments() throws {
    let json = #"[{"testIdentifier": "Suite/test()"}, {"testIdentifier": "Suite/other()", "attachments": [{"exportedFileName": "a.png", "suggestedHumanReadableName": "other.A_0_0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0.png", "isAssociatedWithFailure": true}]}]"#
    let manifest = try JSONDecoder().decode([ManifestEntry].self, from: Data(json.utf8))
    #expect(manifest.count == 2)
    #expect(BaselinePlanner.plan(manifest: manifest).map(\.fileName) == ["other.A.png"])
  }

  @Test func placesFilesUnderSuiteDirectories() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let export = root.appendingPathComponent("export")
    let snapshots = root.appendingPathComponent("__Snapshots__")
    try FileManager.default.createDirectory(at: export, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try Data("new".utf8).write(to: export.appendingPathComponent("x.png"))

    let placement = BaselinePlacement(suite: "Suite", fileName: "test.Name.png", exportedFileName: "x.png")
    let destination = snapshots.appendingPathComponent("Suite/test.Name.png")
    try FileManager.default.createDirectory(
      at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("old".utf8).write(to: destination)

    let written = try BaselinePlanner.place([placement], from: export, into: snapshots)
    #expect(written.map(\.path) == [destination.path])
    #expect(try Data(contentsOf: destination) == Data("new".utf8))
  }
}
