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

/// Checks that a value still looks the way its reference says, and records an issue when it
/// does not.
///
/// ```swift
/// @Test @MainActor func profile() async {
///   await expectSnapshot(of: ProfileView(user: .sample), as: .image(layout: .fixed(width: 390, height: 844)))
/// }
/// ```
///
/// The reference lives in `__Snapshots__/<source file name>/<test name>.<name>.<extension>`
/// next to the source file. A test without a reference fails; what happens besides that depends
/// on ``SnapshotConfiguration/recording``.
///
/// The test goes on after a failure, so one run reports every snapshot that changed.
///
/// - Parameters:
///   - value: The value to take a snapshot of. It is not evaluated when only the existence of
///     the reference is checked.
///   - strategy: How the snapshot is taken and compared.
///   - name: Tells apart the snapshots of one test. Unnamed snapshots are numbered.
///   - testName: The first part of the reference file name. The default is the name of the
///     test that is running.
///   - filePath: A source file. Its name and location decide where the reference is kept,
///     unless ``SnapshotConfiguration/directory`` says otherwise. Pass it on when the call is
///     wrapped in a helper that lives in another file.
///   - fileID: The file the issue is attributed to.
///   - function: The first part of the reference file name when no test is running and
///     `testName` is not given.
///   - line: The line the issue is attributed to.
///   - column: The column the issue is attributed to.
/// - Returns: The failure, when there was one.
@MainActor
@discardableResult
public func expectSnapshot<Value>(
  of value: @autoclosure () throws -> Value,
  as strategy: SnapshotStrategy<Value>,
  named name: String? = nil,
  testName: String? = nil,
  fileID: StaticString = #fileID,
  filePath: StaticString = #filePath,
  function: String = #function,
  line: UInt = #line,
  column: UInt = #column
) async -> SnapshotFailure? {
  let failure = await snapshotFailure(
    of: try value(), as: strategy, named: name, testName: testName, filePath: filePath,
    function: function)
  guard let failure else { return nil }
  let sourceLocation = SourceLocation(
    fileID: "\(fileID)", filePath: "\(filePath)", line: Int(line), column: Int(column))
  for attachment in failure.attachments {
    Attachment.record(
      attachment.data,
      named: SnapshotAttachment.name(
        kind: attachment.kind, directory: failure.directoryName, fileName: failure.fileName),
      sourceLocation: sourceLocation
    )
  }
  Issue.record(Comment(rawValue: failure.message), sourceLocation: sourceLocation)
  return failure
}

/// Checks that a value still looks the way its reference says, and throws when it does not.
///
/// Use it when the rest of the test makes no sense after a failed snapshot. See
/// ``expectSnapshot(of:as:named:testName:fileID:filePath:function:line:column:)`` for the
/// parameters.
///
/// - Throws: ``SnapshotFailure``.
@MainActor
public func requireSnapshot<Value>(
  of value: @autoclosure () throws -> Value,
  as strategy: SnapshotStrategy<Value>,
  named name: String? = nil,
  testName: String? = nil,
  fileID: StaticString = #fileID,
  filePath: StaticString = #filePath,
  function: String = #function,
  line: UInt = #line,
  column: UInt = #column
) async throws {
  let failure = await expectSnapshot(
    of: try value(), as: strategy, named: name, testName: testName, fileID: fileID,
    filePath: filePath,
    function: function, line: line, column: column)
  if let failure { throw failure }
}

/// Takes the snapshot and decides, without reporting anything to the test framework.
@MainActor
func snapshotFailure<Value>(
  of value: @autoclosure () throws -> Value,
  as strategy: SnapshotStrategy<Value>,
  named name: String?,
  testName: String?,
  filePath: StaticString,
  function: String,
  configuration: SnapshotConfiguration = .current
) async -> SnapshotFailure? {
  let testName = testName ?? Test.current?.name ?? function
  let directory = configuration.directory ?? .nextToSourceFile(filePath)
  let snapshotName = name ?? "\(configuration.counter.next(for: "\(directory)|\(testName)"))"
  let location = ReferenceLocation(
    directory: directory, testName: testName, snapshotName: snapshotName,
    pathExtension: strategy.pathExtension)

  return await SnapshotVerifier(configuration: configuration, location: location).verify(
    snapshotName: name ?? location.fileName,
    pathExtension: strategy.pathExtension,
    validate: strategy.validate,
    compare: { reference, actual in strategy.compare(reference, actual, configuration) },
    encode: { try await strategy.encode(try value(), configuration) }
  )
}
