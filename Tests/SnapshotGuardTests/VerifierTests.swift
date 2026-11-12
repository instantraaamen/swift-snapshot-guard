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

import CoreGraphics
import Foundation
import Testing

@testable import SnapshotGuard

/// The decisions a snapshot test makes. Each case below went wrong in a real project before it
/// was written down here.
@MainActor
@Suite struct VerifierTests {
  // MARK: Missing references

  @Test func aMissingReferenceFailsAndIsRecorded() async throws {
    let directory = TemporaryDirectory()
    let failure = try #require(await verify("hello", as: .text, in: directory))
    #expect(failure.reason == .missingReference(recorded: true))
    #expect(directory.files == ["test.shot.txt"])
    #expect(failure.attachments.map(\.kind) == [.recorded])
    #expect(failure.fileName == "test.shot.txt")
    #expect(failure.directoryName == directory.url.lastPathComponent)
  }

  /// A test plan that retries failed tests ran the test again in the same process. The second
  /// attempt found the file the first one had just written, compared the snapshot with
  /// itself, and passed. The suite reported hundreds of passing tests with no references at all.
  @Test func aRetryDoesNotPassAgainstTheReferenceItRecorded() async throws {
    let directory = TemporaryDirectory()
    let first = try #require(await verify("hello", as: .text, in: directory))
    #expect(first.reason == .missingReference(recorded: true))

    let retry = try #require(await verify("hello", as: .text, in: directory))
    #expect(retry.reason == .recordedOnly)
    let again = try #require(await verify("hello", as: .text, in: directory))
    #expect(again.reason == .recordedOnly)
  }

  /// On CI nothing is written next to the references, so there is nothing for a retry to
  /// find. The snapshot travels as an attachment instead.
  @Test func withRecordingOffNothingIsWritten() async throws {
    let directory = TemporaryDirectory()
    for _ in 0..<2 {
      let failure = try #require(await verify("hello", as: .text, in: directory, recording: .never))
      #expect(failure.reason == .missingReference(recorded: false))
      #expect(failure.attachments.map(\.kind) == [.recorded])
      #expect(failure.message.contains("snapshot-guard fetch"))
    }
    #expect(directory.files.isEmpty)
  }

  // MARK: Existing references

  @Test func aMatchingReferencePasses() async throws {
    let directory = TemporaryDirectory()
    try Data("hello".utf8).write(to: directory.url.appendingPathComponent("test.shot.txt"))
    #expect(await verify("hello", as: .text, in: directory) == nil)
    #expect(await verify("hello", as: .text, in: directory, recording: .never) == nil)
  }

  @Test func aDifferentReferenceFailsAndIsLeftAlone() async throws {
    let directory = TemporaryDirectory()
    let reference = directory.url.appendingPathComponent("test.shot.txt")
    try Data("one\ntwo\nthree".utf8).write(to: reference)

    let failure = try #require(await verify("one\n2\nthree", as: .text, in: directory))
    #expect(failure.reason == .mismatch)
    #expect(failure.message.contains("from line 2 on: “2” instead of “two”"))
    #expect(failure.attachments.map(\.kind) == [.actual, .reference])
    #expect(try Data(contentsOf: reference) == Data("one\ntwo\nthree".utf8))
  }

  /// Recording everything again must not look like a verification that passed.
  @Test func recordingAllReplacesTheReferenceAndStillFails() async throws {
    let directory = TemporaryDirectory()
    let reference = directory.url.appendingPathComponent("test.shot.txt")
    try Data("old".utf8).write(to: reference)

    let failure = try #require(await verify("new", as: .text, in: directory, recording: .all))
    #expect(failure.reason == .rerecorded)
    #expect(try Data(contentsOf: reference) == Data("new".utf8))
  }

  // MARK: Checking that references exist

  /// Image suites were skipped on developer machines, where pixels do not compare. A reference
  /// that was deleted for re-recording and then forgotten went unnoticed until the next run on
  /// CI, weeks later in one case. Checking only for existence works on every machine.
  @Test func existenceCanBeCheckedWithoutTakingTheSnapshot() async throws {
    let directory = TemporaryDirectory()
    struct MustNotRender: Error {}
    let strategy = SnapshotStrategy<String>(pathExtension: "txt") { _, _ in throw MustNotRender() }

    let missing = try #require(
      await verify("x", as: strategy, in: directory, verification: .referenceExists))
    #expect(missing.reason == .missingReference(recorded: false))
    #expect(missing.attachments.isEmpty)
    #expect(directory.files.isEmpty)

    try Data("anything".utf8).write(to: directory.url.appendingPathComponent("test.shot.txt"))
    #expect(await verify("x", as: strategy, in: directory, verification: .referenceExists) == nil)
  }

  @Test func aValueThatCannotBeEncodedFails() async throws {
    struct Broken: Error {}
    let strategy = SnapshotStrategy<String>(pathExtension: "txt") { _, _ in throw Broken() }
    let failure = try #require(await verify("x", as: strategy, in: TemporaryDirectory()))
    #expect(failure.reason == .encodingFailed)
  }

  // MARK: Images

  @Test func anImageMatchesItsReferenceWithinTheTolerance() async throws {
    let directory = TemporaryDirectory()
    let image = makeImage(width: 10, height: 10)
    _ = await verify(image, as: .image(), in: directory)
    #expect(directory.files == ["test.shot.png"])

    let fresh = TemporaryDirectory()
    try FileManager.default.copyItem(
      at: directory.url.appendingPathComponent("test.shot.png"),
      to: fresh.url.appendingPathComponent("test.shot.png"))
    #expect(await verify(image, as: .image(), in: fresh) == nil)

    let changed = makeImage(width: 10, height: 10) { x, y in
      x == 0 && y == 0 ? (0, 0, 0, 255) : (UInt8(x * 20), UInt8(y * 20), 90, 255)
    }
    let failure = try #require(await verify(changed, as: .image(), in: fresh))
    #expect(failure.reason == .mismatch)
    #expect(failure.message.contains("1 of 100 pixels differ (1.000%, allowed 0.000%)"))
    #expect(failure.attachments.map(\.kind) == [.actual, .reference, .difference])

    #expect(await verify(changed, as: .image(tolerance: .pixels(0.01)), in: fresh) == nil)
    // The tolerance of the suite applies when the strategy sets none.
    #expect(await verify(changed, as: .image(), in: fresh, imageTolerance: .pixels(0.01)) == nil)
    #expect(
      await verify(changed, as: .image(tolerance: .exact), in: fresh, imageTolerance: .pixels(0.01))
        != nil)
  }

  /// A third of a suite's references once turned out to be the same blank image: the views
  /// had not drawn, and a blank image compares equal to a blank reference forever.
  @Test func aBlankImageIsRejectedBeforeItBecomesAReference() async throws {
    let directory = TemporaryDirectory()
    let blank = makeImage { _, _ in (255, 255, 255, 255) }
    let failure = try #require(await verify(blank, as: .image(), in: directory))
    #expect(failure.reason == .invalid)
    #expect(directory.files.isEmpty)

    let allowed = try #require(
      await verify(blank, as: .image(allowsUniformImage: true), in: directory))
    #expect(allowed.reason == .missingReference(recorded: true))
  }

  @Test func aSizeChangeIsReportedAsSuch() async throws {
    let directory = TemporaryDirectory()
    _ = await verify(makeImage(width: 10, height: 10), as: .image(), in: directory)
    let fresh = TemporaryDirectory()
    try FileManager.default.copyItem(
      at: directory.url.appendingPathComponent("test.shot.png"),
      to: fresh.url.appendingPathComponent("test.shot.png"))

    let failure = try #require(
      await verify(makeImage(width: 10, height: 12), as: .image(), in: fresh))
    #expect(failure.message.contains("The image is 10×12 pixels and the reference is 10×10."))
  }

  /// A reference recorded on another system version differs in every line of text. Saying so
  /// saves the search for a change in the app that is not there.
  @Test func aReferenceFromAnotherEnvironmentIsCalledOut() throws {
    let recorded = RecordingEnvironment(system: "iOS 17.0", device: "iPhone15,2", scale: 3)
    let reference = try #require(PNG.encode(makeBitmap(), environment: recorded))
    let actual = try #require(
      PNG.encode(makeBitmap { _, _ in (1, 2, 3, 255) }, environment: .current(scale: 3)))

    let mismatch = try #require(
      ImageMismatch.describe(reference: reference, actual: actual, tolerance: .exact))
    #expect(mismatch.message.contains("The reference was recorded in another environment"))
    #expect(mismatch.message.contains("instead of iOS 17.0"))
  }
}

@Suite struct ReferenceLocationTests {
  private func fileSystem(checkout: Bool, bundled: [String] = []) -> ReferenceLocation.FileSystem {
    .init(
      directoryExists: { _ in checkout },
      bundleResource: { name, pathExtension in
        bundled.contains("\(name).\(pathExtension)")
          ? URL(fileURLWithPath: "/Tests.xctest/\(name).\(pathExtension)") : nil
      })
  }

  @Test func namesFollowTheTestAndTheSnapshot() {
    #expect(ReferenceLocation.sanitize("profile()") == "profile")
    #expect(ReferenceLocation.sanitize("Profile_en") == "Profile_en")
    #expect(ReferenceLocation.sanitize("shows(user:) twice") == "shows-user-twice")
    #expect(ReferenceLocation.sanitize("設定 画面") == "設定-画面")
  }

  @Test func referencesLiveNextToTheSourceFile() {
    let location = ReferenceLocation(
      directory: .nextToSourceFile("/repo/Tests/ProfileSnapshotTests.swift"),
      testName: "profile()", snapshotName: "Profile_en", pathExtension: "png",
      fileSystem: fileSystem(checkout: true))
    #expect(location.fileName == "profile.Profile_en.png")
    #expect(location.directoryName == "ProfileSnapshotTests")
    #expect(
      location.writable?.path
        == "/repo/Tests/__Snapshots__/ProfileSnapshotTests/profile.Profile_en.png")
    #expect(location.candidates == [location.writable])
  }

  /// With the checkout at hand, a reference that only exists in the test bundle is not a
  /// reference: it was never added to the repository. Falling back to the bundle here once
  /// recorded new references into the build products, where they were lost.
  @Test func theBundleIsNotConsultedWhenTheCheckoutIsThere() {
    let location = ReferenceLocation(
      directory: .nextToSourceFile("/repo/Tests/ProfileSnapshotTests.swift"),
      testName: "profile()", snapshotName: "Profile_en", pathExtension: "png",
      fileSystem: fileSystem(checkout: true, bundled: ["profile.Profile_en.png"]))
    #expect(
      location.candidates.map(\.path) == [
        "/repo/Tests/__Snapshots__/ProfileSnapshotTests/profile.Profile_en.png"
      ])
  }

  /// A CI service that builds on one machine and tests on another has no checkout where the
  /// tests run. The references come from the test bundle, and nothing can be recorded.
  @Test func withoutACheckoutTheBundleIsReadAndNothingIsWritten() {
    let location = ReferenceLocation(
      directory: .nextToSourceFile("/repo/Tests/ProfileSnapshotTests.swift"),
      testName: "profile()", snapshotName: "Profile_en", pathExtension: "png",
      fileSystem: fileSystem(checkout: false, bundled: ["profile.Profile_en.png"]))
    #expect(location.candidates.map(\.path) == ["/Tests.xctest/profile.Profile_en.png"])
    #expect(location.writable == nil)
    #expect(location.directoryName == "ProfileSnapshotTests")

    let missing = ReferenceLocation(
      directory: .nextToSourceFile("/repo/Tests/ProfileSnapshotTests.swift"),
      testName: "profile()", snapshotName: "Other", pathExtension: "png",
      fileSystem: fileSystem(checkout: false))
    #expect(missing.candidates.isEmpty)
    #expect(missing.searchedDescription.contains("in the test bundle"))
  }
}

@MainActor
@Suite(.snapshots(recording: .never, imageTolerance: .pixels(0.5)))
struct TraitTests {
  @Test func theTraitSetsTheConfigurationOfTheTest() {
    #expect(SnapshotConfiguration.current.recording == .never)
    #expect(SnapshotConfiguration.current.imageTolerance == .pixels(0.5))
  }

  @Test(.snapshots(recording: .all)) func aTestOverridesItsSuiteAndKeepsTheRest() {
    #expect(SnapshotConfiguration.current.recording == .all)
    #expect(SnapshotConfiguration.current.imageTolerance == .pixels(0.5))
  }

  @Test func unnamedSnapshotsAreNumberedFromOneInEveryRun() async throws {
    let directory = TemporaryDirectory()
    var configuration = SnapshotConfiguration.current
    configuration.recording = .missing
    configuration.directory = .at(directory.url)
    for text in ["a", "b"] {
      _ = await snapshotFailure(
        of: text, as: .text, named: nil, testName: "test()", filePath: #filePath,
        function: #function,
        configuration: configuration)
    }
    #expect(directory.files == ["test.1.txt", "test.2.txt"])
  }

  /// Failures are reported to the test, with the files that `snapshot-guard fetch` looks for.
  @Test func aFailureIsRecordedAsAnIssueWithNamedAttachments() async {
    let directory = TemporaryDirectory()
    await withKnownIssue { () async in
      await SnapshotConfiguration.$current.withValue(
        SnapshotConfiguration(recording: .never, directory: .at(directory.url))
      ) {
        let failure = await expectSnapshot(of: "hello", as: .text, named: "Greeting")
        #expect(failure?.fileName == "aFailureIsRecordedAsAnIssueWithNamedAttachments.Greeting.txt")
      }
    }
    #expect(
      SnapshotAttachment.name(
        kind: .recorded, directory: "ProfileSnapshotTests", fileName: "profile.Profile_en.png")
        == "recorded~ProfileSnapshotTests~profile.Profile_en.png")
  }

  @Test func requireThrowsTheFailure() async {
    let directory = TemporaryDirectory()
    let configuration = SnapshotConfiguration(recording: .never, directory: .at(directory.url))
    await withKnownIssue { () async in
      await SnapshotConfiguration.$current.withValue(configuration) {
        do {
          try await requireSnapshot(of: "hello", as: .text)
          Issue.record("requireSnapshot did not throw")
        } catch {
          #expect(error is SnapshotFailure)
        }
      }
    }
  }
}
