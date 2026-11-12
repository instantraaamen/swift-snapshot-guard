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
