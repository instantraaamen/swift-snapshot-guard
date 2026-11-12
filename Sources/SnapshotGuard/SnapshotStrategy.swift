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

/// How a value is turned into a snapshot and how two snapshots are compared.
///
/// The library ships strategies for images, text and data. Make your own for another format:
///
/// ```swift
/// extension SnapshotStrategy where Value: Encodable {
///   static var json: SnapshotStrategy {
///     SnapshotStrategy(pathExtension: "json") { value, _ in
///       let encoder = JSONEncoder()
///       encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
///       return try encoder.encode(value)
///     }
///   }
/// }
/// ```
public struct SnapshotStrategy<Value>: Sendable {
  /// Turns a value into the bytes that are stored as its reference.
  public typealias Encode = @MainActor @Sendable (Value, SnapshotConfiguration) async throws -> Data
  /// Compares the stored reference with the bytes of this run. Returns `nil` when they match.
  public typealias Compare =
    @Sendable (_ reference: Data, _ actual: Data, SnapshotConfiguration) -> SnapshotMismatch?
  /// Looks at the bytes of this run before they are compared or recorded. Returns a reason to
  /// reject them, or `nil`.
  public typealias Validate = @Sendable (_ actual: Data) -> String?

  /// The file extension of the reference, without a dot.
  public var pathExtension: String
  var encode: Encode
  var compare: Compare
  var validate: Validate

  /// Creates a strategy.
  ///
  /// - Parameters:
  ///   - pathExtension: The file extension of the reference, without a dot.
  ///   - validate: Rejects a snapshot that cannot be right, whatever the reference says.
  ///   - compare: Compares the reference with this run. The default requires equal bytes.
  ///   - encode: Turns a value into the bytes that are stored.
  public init(
    pathExtension: String,
    validate: @escaping Validate = { _ in nil },
    compare: @escaping Compare = { reference, actual, _ in
      reference == actual
        ? nil
        : SnapshotMismatch(
          message:
            "The snapshot differs from its reference (\(actual.count) bytes, reference \(reference.count) bytes)."
        )
    },
    encode: @escaping Encode
  ) {
    self.pathExtension = pathExtension
    self.validate = validate
    self.compare = compare
    self.encode = encode
  }

  /// Returns a strategy for another type that converts its values and then uses this one.
  public func pullback<NewValue>(
    _ transform: @escaping @MainActor @Sendable (NewValue) throws -> Value
  ) -> SnapshotStrategy<NewValue> {
    SnapshotStrategy<NewValue>(pathExtension: pathExtension, validate: validate, compare: compare) {
      value, configuration in
      try await encode(try transform(value), configuration)
    }
  }
}

/// Why a snapshot does not match its reference.
public struct SnapshotMismatch: Sendable {
  /// What differs, in a sentence or two.
  public var message: String
  /// Files that help to see the difference, such as an image of the differing pixels.
  public var attachments: [SnapshotAttachment]

  public init(message: String, attachments: [SnapshotAttachment] = []) {
    self.message = message
    self.attachments = attachments
  }
}

/// A file that is attached to a test for a snapshot.
public struct SnapshotAttachment: Sendable {
  /// What the file shows. `snapshot-guard fetch` reads the kind to tell references to adopt
  /// from files that are only there to look at.
  public enum Kind: String, Sendable, CaseIterable {
    /// What this run produced when there was no reference to compare with.
    case recorded
    /// What this run produced when it did not match the reference.
    case actual
    /// The reference that this run did not match.
    case reference
    /// Where the two differ.
    case difference
  }

  public var kind: Kind
  public var data: Data
  /// The file extension, without a dot.
  public var pathExtension: String

  public init(kind: Kind, data: Data, pathExtension: String) {
    self.kind = kind
    self.data = data
    self.pathExtension = pathExtension
  }

  /// The separator between the parts of an attachment's name. It does not occur in the
  /// sanitized names of tests and snapshots.
  public static let nameSeparator = "~"

  /// The name an attachment is recorded under: `<kind>~<directory>~<reference file name>`.
  public static func name(kind: Kind, directory: String, fileName: String) -> String {
    [kind.rawValue, directory, fileName].joined(separator: nameSeparator)
  }
}

extension SnapshotStrategy where Value == Data {
  /// Stores the bytes as they are, and requires equal bytes.
  public static var data: SnapshotStrategy {
    SnapshotStrategy(pathExtension: "bin") { value, _ in value }
  }
}

extension SnapshotStrategy where Value == String {
  /// Stores the text as UTF-8, and reports the first line that differs.
  public static var text: SnapshotStrategy {
    SnapshotStrategy(
      pathExtension: "txt",
      compare: { reference, actual, _ in
        guard reference != actual else { return nil }
        let old = String(decoding: reference, as: UTF8.self).components(separatedBy: "\n")
        let new = String(decoding: actual, as: UTF8.self).components(separatedBy: "\n")
        let line =
          zip(old, new).enumerated().first { $0.element.0 != $0.element.1 }?.offset
          ?? min(old.count, new.count)
        func text(_ lines: [String]) -> String {
          line < lines.count ? "“\(lines[line])”" : "nothing"
        }
        return SnapshotMismatch(
          message:
            "The text differs from its reference from line \(line + 1) on: \(text(new)) instead of \(text(old)).",
          attachments: [
            SnapshotAttachment(kind: .actual, data: actual, pathExtension: "txt"),
            SnapshotAttachment(kind: .reference, data: reference, pathExtension: "txt"),
          ])
      },
      encode: { value, _ in Data(value.utf8) }
    )
  }
}
