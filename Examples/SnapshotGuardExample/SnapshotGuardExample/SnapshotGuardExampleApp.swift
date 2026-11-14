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

import SwiftUI

@main
struct SnapshotGuardExampleApp: App {
  var body: some Scene {
    WindowGroup {
      ProfileCard(profile: .sample)
        .padding()
    }
  }
}

enum Example {
  /// Run the tests with `EXAMPLE_CHANGED=1` in the environment to draw the card a little
  /// differently. That stands in for a change nobody meant to make, without editing the code.
  static let isChanged = ProcessInfo.processInfo.environment["EXAMPLE_CHANGED"] == "1"
}
