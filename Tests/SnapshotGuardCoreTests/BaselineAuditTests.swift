import CryptoKit
import Foundation
import Testing

@testable import SnapshotGuardCore

@Suite struct BaselineAuditTests {
  private func makeTree(_ files: [String: String]) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    for (path, contents) in files {
      let url = root.appendingPathComponent(path)
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(contents.utf8).write(to: url)
    }
    return root
  }

  @Test func cleanTreeHasNoFindings() throws {
    let root = try makeTree(["A/a.one.png": "1", "B/b.two.png": "2", "B/notes.txt": "1"])
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(try BaselineAudit.audit(directory: root).isClean)
  }

  @Test func reportsIdenticalBytes() throws {
    let root = try makeTree(["A/a.one.png": "blank", "B/b.two.png": "blank", "B/b.three.png": "drawn"])
    defer { try? FileManager.default.removeItem(at: root) }
    let audit = try BaselineAudit.audit(directory: root)
    #expect(audit.identicalFiles.map { $0.map(\.lastPathComponent) } == [["a.one.png", "b.two.png"]])
    #expect(audit.nameCollisions.isEmpty)
  }

  @Test func reportsNameCollisionsAcrossSuites() throws {
    let root = try makeTree(["A/test.Screen.png": "1", "B/test.Screen.png": "2"])
    defer { try? FileManager.default.removeItem(at: root) }
    let audit = try BaselineAudit.audit(directory: root)
    #expect(audit.nameCollisions.count == 1)
    #expect(audit.identicalFiles.isEmpty)
  }
}

@Suite struct AppStoreConnectKeyTests {
  @Test func tokenIsSignedWithTheKey() throws {
    let privateKey = P256.Signing.PrivateKey()
    let key = AppStoreConnectKey(keyID: "KEY", issuerID: "ISSUER", privateKeyPEM: privateKey.pemRepresentation)
    let token = try key.token(now: Date(timeIntervalSince1970: 1_000))
    let parts = token.split(separator: ".").map(String.init)
    #expect(parts.count == 3)

    func decode(_ text: String) throws -> Data {
      var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
      base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
      return try #require(Data(base64Encoded: base64))
    }

    let header = try JSONSerialization.jsonObject(with: decode(parts[0])) as? [String: String]
    #expect(header == ["alg": "ES256", "kid": "KEY", "typ": "JWT"])
    let payload = try #require(JSONSerialization.jsonObject(with: decode(parts[1])) as? [String: Any])
    #expect(payload["iss"] as? String == "ISSUER")
    #expect(payload["aud"] as? String == "appstoreconnect-v1")
    #expect(payload["exp"] as? Int == 1_600)

    let signature = try P256.Signing.ECDSASignature(rawRepresentation: decode(parts[2]))
    #expect(privateKey.publicKey.isValidSignature(signature, for: Data("\(parts[0]).\(parts[1])".utf8)))
  }

  @Test func readsFastlaneEnvironmentNames() throws {
    let key = try AppStoreConnectKey.fromEnvironment([
      "APP_STORE_CONNECT_API_KEY_KEY_ID": "KEY",
      "APP_STORE_CONNECT_API_KEY_ISSUER_ID": "ISSUER",
      "APP_STORE_CONNECT_API_KEY_KEY": "PEM",
    ])
    #expect(key.keyID == "KEY")
    #expect(key.privateKeyPEM == "PEM")
    #expect(throws: AppStoreConnectError.self) {
      try AppStoreConnectKey.fromEnvironment([:])
    }
  }

  @Test func picksTestResultArchives() {
    #expect(XcodeCloud.isTestResultArchive("Test-App-iOS-XCResult.zip"))
    #expect(!XcodeCloud.isTestResultArchive("App-build-for-testing-XCResult.zip"))
    #expect(!XcodeCloud.isTestResultArchive("Logs.zip"))
  }
}
