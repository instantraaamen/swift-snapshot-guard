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

import SnapshotGuard
import SwiftUI
import Testing

@testable import SnapshotGuardExample

/// The references are kept next to this file, in `__Snapshots__/ProfileCardSnapshotTests`.
///
/// `recording` is left at its default, `.missing`: a test without a reference writes one and
/// fails, and passes from the next run on. On CI you would pass `recording: .never`.
@MainActor
@Suite(.snapshots())
struct ProfileCardSnapshotTests {
  @Test func light() async {
    await expectSnapshot(
      of: ProfileCard(profile: .sample).padding(),
      as: .image(layout: .fixed(width: 390, height: 300))
    )
  }

  @Test func dark() async {
    await expectSnapshot(
      of: ProfileCard(profile: .sample).padding(),
      as: .image(layout: .fixed(width: 390, height: 300), traits: { $0.userInterfaceStyle = .dark })
    )
  }

  @Test func summary() async {
    await expectSnapshot(of: Profile.sample.summary, as: .text)
  }
}
