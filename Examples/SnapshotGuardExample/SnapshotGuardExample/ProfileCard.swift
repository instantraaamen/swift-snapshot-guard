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

struct Profile: Sendable {
  var name: String
  var role: String
  var followers: Int
  var following: Int

  static let sample = Profile(name: "Ada Lovelace", role: "Analyst", followers: 1815, following: 36)

  /// What a screen reader would say about the card.
  var summary: String {
    """
    \(name), \(role)
    \(followers) followers
    \(following) following
    """
  }
}

/// The view the snapshot tests look at.
struct ProfileCard: View {
  var profile: Profile
  var isChanged = Example.isChanged

  var body: some View {
    VStack(spacing: isChanged ? 20 : 16) {
      Circle()
        .fill(isChanged ? Color.indigo : Color.blue)
        .frame(width: 72, height: 72)
        .overlay {
          Text(profile.name.prefix(1))
            .font(.largeTitle.bold())
            .foregroundStyle(.white)
        }
      VStack(spacing: 4) {
        Text(profile.name).font(.title2.bold())
        Text(profile.role).foregroundStyle(.secondary)
      }
      HStack(spacing: 32) {
        count(profile.followers, "Followers")
        count(profile.following, "Following")
      }
    }
    .padding(24)
    .frame(maxWidth: .infinity)
    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
  }

  private func count(_ value: Int, _ label: String) -> some View {
    VStack(spacing: 2) {
      Text("\(value)").font(.headline)
      Text(label).font(.caption).foregroundStyle(.secondary)
    }
  }
}

#Preview {
  ProfileCard(profile: .sample).padding()
}
