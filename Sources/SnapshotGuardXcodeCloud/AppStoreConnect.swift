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

/// An App Store Connect API key.
public struct AppStoreConnectKey: Sendable {
  public var keyID: String
  public var issuerID: String
  /// The contents of the `.p8` file.
  public var privateKeyPEM: String

  public init(keyID: String, issuerID: String, privateKeyPEM: String) {
    self.keyID = keyID
    self.issuerID = issuerID
    self.privateKeyPEM = privateKeyPEM
  }

  /// Reads the key from the environment, using the variable names fastlane uses:
  /// `APP_STORE_CONNECT_API_KEY_KEY_ID`, `APP_STORE_CONNECT_API_KEY_ISSUER_ID`, and either
  /// `APP_STORE_CONNECT_API_KEY_KEY_FILEPATH` or `APP_STORE_CONNECT_API_KEY_KEY`.
  public static func fromEnvironment(
    _ environment: [String: String] = ProcessInfo.processInfo.environment
  ) throws -> AppStoreConnectKey {
    let prefix = "APP_STORE_CONNECT_API_KEY_"
    guard let keyID = environment[prefix + "KEY_ID"], !keyID.isEmpty else {
      throw AppStoreConnectError.missingEnvironment(prefix + "KEY_ID")
    }
    guard let issuerID = environment[prefix + "ISSUER_ID"], !issuerID.isEmpty else {
      throw AppStoreConnectError.missingEnvironment(prefix + "ISSUER_ID")
    }
    let pem: String
    if let path = environment[prefix + "KEY_FILEPATH"], !path.isEmpty {
      pem = try String(contentsOfFile: (path as NSString).expandingTildeInPath, encoding: .utf8)
    } else if let key = environment[prefix + "KEY"], !key.isEmpty {
      pem = key
    } else {
      throw AppStoreConnectError.missingEnvironment(prefix + "KEY_FILEPATH")
    }
    return AppStoreConnectKey(keyID: keyID, issuerID: issuerID, privateKeyPEM: pem)
  }

  /// Creates a signed token for the App Store Connect API.
  public func token(now: Date = Date(), lifetime: TimeInterval = 600) throws -> String {
    let header: [String: String] = ["alg": "ES256", "kid": keyID, "typ": "JWT"]
    let issuedAt = Int(now.timeIntervalSince1970)
    let payload: [String: Any] = [
      "iss": issuerID,
      "iat": issuedAt,
      "exp": issuedAt + Int(lifetime),
      "aud": "appstoreconnect-v1",
    ]
    let signingInput =
      try Self.base64URL(JSONSerialization.data(withJSONObject: header, options: .sortedKeys))
      + "."
      + Self.base64URL(JSONSerialization.data(withJSONObject: payload, options: .sortedKeys))
    let key = try P256.Signing.PrivateKey(pemRepresentation: privateKeyPEM)
    let signature = try key.signature(for: Data(signingInput.utf8))
    return signingInput + "." + Self.base64URL(signature.rawRepresentation)
  }

  static func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}

public enum AppStoreConnectError: Error, CustomStringConvertible {
  case missingEnvironment(String)
  case http(status: Int, url: URL, body: String)
  case notFound(String)
  /// The API pointed at a URL outside itself. The token is not sent there.
  case untrustedURL(URL)

  public var description: String {
    switch self {
    case .missingEnvironment(let name):
      return "The environment variable \(name) is not set."
    case .http(let status, let url, let body):
      return "App Store Connect returned \(status) for \(url.path).\n\(body)"
    case .notFound(let what):
      return what
    case .untrustedURL(let url):
      let host = url.host ?? "an unknown host"
      return "App Store Connect pointed at \(host), which is not the API. The request was not sent."
    }
  }
}

/// A minimal JSON:API document, enough for the Xcode Cloud endpoints.
struct APIDocument: Decodable {
  struct Resource: Decodable {
    var id: String
    var attributes: Attributes?
  }
  struct Attributes: Decodable {
    var name: String?
    var number: Int?
    var executionProgress: String?
    var fileName: String?
    var fileSize: Int?
    var downloadUrl: URL?
  }
  struct Links: Decodable {
    var next: URL?
  }
  var data: [Resource]
  var links: Links?
}

struct AppStoreConnectClient: Sendable {
  var key: AppStoreConnectKey
  var baseURL = URL(string: "https://api.appstoreconnect.apple.com/v1")!

  func get(_ path: String, query: [String: String] = [:]) async throws -> APIDocument {
    var components = URLComponents(
      url: baseURL.appendingPathComponent(path),
      resolvingAgainstBaseURL: false
    )!
    if !query.isEmpty {
      components.queryItems = query.sorted { $0.key < $1.key }.map {
        URLQueryItem(name: $0.key, value: $0.value)
      }
    }
    return try await get(components.url!)
  }

  /// Whether a request to `url` may carry the token: only HTTPS, and only the host of the API.
  ///
  /// The URLs of further pages come from responses. They are checked here, so that a response
  /// cannot direct the token anywhere else.
  func isTrusted(_ url: URL) -> Bool {
    guard let host = url.host, let apiHost = baseURL.host else { return false }
    return url.scheme?.lowercased() == "https" && host.lowercased() == apiHost.lowercased()
      && url.port == baseURL.port && url.user == nil
  }

  func get(_ url: URL) async throws -> APIDocument {
    guard isTrusted(url) else { throw AppStoreConnectError.untrustedURL(url) }
    var request = URLRequest(url: url)
    request.setValue("Bearer \(try key.token())", forHTTPHeaderField: "Authorization")
    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status) else {
      throw AppStoreConnectError.http(
        status: status, url: url, body: String(decoding: data, as: UTF8.self))
    }
    return try JSONDecoder().decode(APIDocument.self, from: data)
  }

  /// Follows `links.next` until `stop` returns a value or the pages run out.
  func firstMatch<T>(
    _ path: String,
    query: [String: String] = [:],
    maxPages: Int = 20,
    _ match: (APIDocument.Resource) -> T?
  ) async throws -> T? {
    var document = try await get(path, query: query)
    for _ in 0..<maxPages {
      for resource in document.data {
        if let found = match(resource) { return found }
      }
      guard let next = document.links?.next else { return nil }
      document = try await get(next)
    }
    return nil
  }

  /// Collects every page.
  func all(_ path: String, query: [String: String] = [:]) async throws -> [APIDocument.Resource] {
    var resources: [APIDocument.Resource] = []
    _ = try await firstMatch(path, query: query) { resource -> Never? in
      resources.append(resource)
      return nil
    }
    return resources
  }
}
