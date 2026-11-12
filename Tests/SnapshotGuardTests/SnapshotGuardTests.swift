import Foundation
import SnapshotTesting
import Testing

@testable import SnapshotGuard

@Suite struct GuardTests {
  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("guard-tests-\(UUID().uuidString)")
  }

  @Test func libraryStillReportsMissingReferences() {
    #expect(SnapshotGuard.missingReferenceCheck() == nil)
  }

  @Test func retryAfterRecordingStillFails() {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    // First attempt: no reference, so the library records one and fails.
    let first = verifyGuardedSnapshot(of: "hello", as: .lines, named: "greeting", snapshotDirectory: directory.path)
    #expect(first?.contains(SnapshotGuard.missingReferenceMarker) == true)

    // Retry: the file now exists and matches, but nothing was really compared.
    let second = verifyGuardedSnapshot(of: "hello", as: .lines, named: "greeting", snapshotDirectory: directory.path)
    #expect(second != nil)
    #expect(second?.contains(SnapshotGuard.missingReferenceMarker) == false)

    // Plain verifySnapshot is what turns green here.
    let unguarded = verifySnapshot(of: "hello", as: .lines, named: "greeting", snapshotDirectory: directory.path)
    #expect(unguarded == nil)
  }

  @Test func existingReferencePasses() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    // Record through the library directly, as if the reference had been committed earlier.
    _ = verifySnapshot(of: "hello", as: .lines, named: "greeting", snapshotDirectory: directory.path)

    #expect(verifyGuardedSnapshot(of: "hello", as: .lines, named: "greeting", snapshotDirectory: directory.path) == nil)
    let mismatch = verifyGuardedSnapshot(of: "bye", as: .lines, named: "greeting", snapshotDirectory: directory.path)
    #expect(mismatch != nil)
  }

  @Test func registryKeepsKeysApart() {
    let registry = RecordedOnlyRegistry()
    let recorded = "\(SnapshotGuard.missingReferenceMarker). Automatically recorded snapshot."
    #expect(registry.resolve(failure: recorded, key: "a") == .failed(recorded))
    #expect(registry.resolve(failure: nil, key: "b") == .matched)
    if case .recordedOnly = registry.resolve(failure: nil, key: "a") {
    } else {
      Issue.record("A snapshot that was only recorded must not pass on retry.")
    }
    // An ordinary mismatch is not remembered.
    #expect(registry.resolve(failure: "Snapshot does not match reference.", key: "c") == .failed("Snapshot does not match reference."))
    #expect(registry.resolve(failure: nil, key: "c") == .matched)
  }
}

@Suite struct SnapshotEnvironmentTests {
  private func environment(
    baseline: String,
    current: String,
    policy: SnapshotEnvironment.Policy = .baselineOSOnly,
    checkout: Bool = true
  ) -> SnapshotEnvironment {
    SnapshotEnvironment(
      baselineOSVersion: baseline,
      policy: policy,
      sourceDirectory: "/repo/Tests",
      currentOSVersion: current,
      fileExists: { _ in checkout }
    )
  }

  @Test func matchesVersionsByComponent() {
    #expect(environment(baseline: "18.2", current: "18.2.0").isBaselineOS)
    #expect(environment(baseline: "18", current: "18.2.1").isBaselineOS)
    #expect(!environment(baseline: "18.2", current: "18.20.0").isBaselineOS)
    #expect(!environment(baseline: "18.2", current: "17.2.0").isBaselineOS)
    #expect(!environment(baseline: "1", current: "18.0.0").isBaselineOS)
  }

  @Test func baselineOSOnlyIgnoresCheckout() {
    #expect(environment(baseline: "18", current: "18.0.0", checkout: true).shouldRun)
    #expect(environment(baseline: "18", current: "18.0.0", checkout: false).shouldRun)
    #expect(!environment(baseline: "18", current: "17.0.0").shouldRun)
  }

  @Test func ciOnlySkipsWhereTheCheckoutIsVisible() {
    #expect(!environment(baseline: "18", current: "18.0.0", policy: .ciOnly, checkout: true).shouldRun)
    #expect(environment(baseline: "18", current: "18.0.0", policy: .ciOnly, checkout: false).shouldRun)
    #expect(!environment(baseline: "18", current: "17.0.0", policy: .ciOnly, checkout: false).shouldRun)
  }

  @Test func publicInitializerSeesThisCheckout() {
    let environment = SnapshotEnvironment(baselineOSVersion: "0")
    #expect(environment.hasRepositoryCheckout)
    #expect(!environment.shouldRun)
  }
}

@Suite struct SnapshotDirectoryTests {
  @Test func prefersTheRepository() {
    let path = SnapshotDirectory.resolve(
      suite: "ScreenTests", fallbackPath: "/bundle", filePath: "/repo/Tests/ScreenTests.swift",
      fileExists: { $0 == "/repo/Tests/__Snapshots__/ScreenTests" })
    #expect(path == "/repo/Tests/__Snapshots__/ScreenTests")
  }

  @Test func fallsBackToTheBundle() {
    let path = SnapshotDirectory.resolve(
      suite: "ScreenTests", fallbackPath: "/bundle", filePath: "/repo/Tests/ScreenTests.swift",
      fileExists: { _ in false })
    #expect(path == "/bundle")
  }
}

@Suite struct CleanUserDefaultsTests {
  @Test func clearsThenRestores() throws {
    let domain = "snapshot-guard-tests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    defaults.set("ja", forKey: "language")

    let seen = withCleanUserDefaults(defaults, domain: domain) { () -> String? in
      let before = defaults.string(forKey: "language")
      defaults.set("temporary", forKey: "scratch")
      return before
    }

    #expect(seen == nil)
    #expect(defaults.string(forKey: "language") == "ja")
    #expect(defaults.string(forKey: "scratch") == nil)
  }
}
