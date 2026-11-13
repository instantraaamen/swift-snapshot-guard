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

import CryptoKit
import Foundation
import Testing

@testable import SnapshotGuardXcodeCloud

@Suite struct AppStoreConnectKeyTests {
  @Test func tokenIsSignedWithTheKey() throws {
    let privateKey = P256.Signing.PrivateKey()
    let key = AppStoreConnectKey(
      keyID: "KEY", issuerID: "ISSUER", privateKeyPEM: privateKey.pemRepresentation)
    let token = try key.token(now: Date(timeIntervalSince1970: 1_000))
    let parts = token.split(separator: ".").map(String.init)
    #expect(parts.count == 3)

    func decode(_ text: String) throws -> Data {
      var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(
        of: "_", with: "/")
      base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
      return try #require(Data(base64Encoded: base64))
    }

    let header = try JSONSerialization.jsonObject(with: decode(parts[0])) as? [String: String]
    #expect(header == ["alg": "ES256", "kid": "KEY", "typ": "JWT"])
    let payload = try #require(
      JSONSerialization.jsonObject(with: decode(parts[1])) as? [String: Any])
    #expect(payload["iss"] as? String == "ISSUER")
    #expect(payload["aud"] as? String == "appstoreconnect-v1")
    #expect(payload["exp"] as? Int == 1_600)

    let signature = try P256.Signing.ECDSASignature(rawRepresentation: decode(parts[2]))
    #expect(
      privateKey.publicKey.isValidSignature(signature, for: Data("\(parts[0]).\(parts[1])".utf8)))
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

  @Test(arguments: [
    "https://api.appstoreconnect.apple.com/v1/ciProducts?cursor=abc",
    "https://API.appstoreconnect.apple.com/v1/ciWorkflows/1/buildRuns",
  ])
  func theTokenGoesToTheAPI(url: String) throws {
    let client = AppStoreConnectClient(
      key: AppStoreConnectKey(keyID: "KEY", issuerID: "ISSUER", privateKeyPEM: "PEM"))
    #expect(client.isTrusted(try #require(URL(string: url))))
  }

  @Test(arguments: [
    "https://example.com/v1/ciProducts",
    "http://api.appstoreconnect.apple.com/v1/ciProducts",
    "https://api.appstoreconnect.apple.com.example.com/v1/ciProducts",
    "https://api.appstoreconnect.apple.com@example.com/v1/ciProducts",
    "https://user@api.appstoreconnect.apple.com/v1/ciProducts",
    "https://api.appstoreconnect.apple.com:8443/v1/ciProducts",
  ])
  func theTokenGoesNowhereElse(url: String) async throws {
    let client = AppStoreConnectClient(
      key: AppStoreConnectKey(keyID: "KEY", issuerID: "ISSUER", privateKeyPEM: "PEM"))
    let url = try #require(URL(string: url))
    #expect(!client.isTrusted(url))
    // Refused before the token is signed or anything is sent.
    await #expect(throws: AppStoreConnectError.self) { _ = try await client.get(url) }
  }
}
