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

/// Runs `body` with an empty persistent domain, then restores the previous contents.
///
/// Snapshot tests that are hosted by the real application share its `UserDefaults`. Clearing
/// the domain makes screens render from a known state, and restoring it keeps the tests from
/// wiping the settings of the app installed on the simulator.
///
/// - Parameters:
///   - defaults: The defaults object to go through.
///   - domain: The persistent domain to clear, usually the host application's bundle identifier.
///   - body: The work to run against the empty domain.
/// - Returns: The value `body` returns.
public func withCleanUserDefaults<Result>(
  _ defaults: UserDefaults = .standard,
  domain: String,
  _ body: () throws -> Result
) rethrows -> Result {
  let saved = defaults.persistentDomain(forName: domain)
  defaults.removePersistentDomain(forName: domain)
  defer {
    defaults.removePersistentDomain(forName: domain)
    if let saved {
      defaults.setPersistentDomain(saved, forName: domain)
    }
  }
  return try body()
}

/// Runs `body` with an empty persistent domain, then restores the previous contents.
///
/// The asynchronous counterpart of ``withCleanUserDefaults(_:domain:_:)-(_,_,()->Result)``, for
/// tests that take snapshots inside it.
public func withCleanUserDefaults<Result>(
  _ defaults: UserDefaults = .standard,
  domain: String,
  isolation: isolated (any Actor)? = #isolation,
  _ body: () async throws -> Result
) async rethrows -> Result {
  let saved = defaults.persistentDomain(forName: domain)
  defaults.removePersistentDomain(forName: domain)
  defer {
    defaults.removePersistentDomain(forName: domain)
    if let saved {
      defaults.setPersistentDomain(saved, forName: domain)
    }
  }
  return try await body()
}
