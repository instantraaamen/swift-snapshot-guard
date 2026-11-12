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

#if canImport(UIKit) && !os(watchOS)
  import SwiftUI
  import UIKit

  /// How a view is rendered for an image snapshot.
  public struct ViewImageOptions: Sendable {
    /// The size the view is given.
    public var layout: SnapshotLayout
    /// The safe area the view sees. The default is none, so that the same view renders the
    /// same way whatever device the tests run on.
    public var safeAreaInsets: UIEdgeInsets
    /// Overrides traits, such as the interface style or the display scale.
    public var traits: (@MainActor @Sendable (inout any UIMutableTraits) -> Void)?
    /// When the view is ready.
    public var settling: SnapshotSettling
    /// How much the image may differ from its reference. `nil` uses
    /// ``SnapshotConfiguration/imageTolerance``.
    public var tolerance: ImageTolerance?
    /// Whether an image of one flat colour is accepted.
    public var allowsUniformImage: Bool

    public init(
      layout: SnapshotLayout = .sizeThatFits,
      safeAreaInsets: UIEdgeInsets = .zero,
      traits: (@MainActor @Sendable (inout any UIMutableTraits) -> Void)? = nil,
      settling: SnapshotSettling = .immediately,
      tolerance: ImageTolerance? = nil,
      allowsUniformImage: Bool = false
    ) {
      self.layout = layout
      self.safeAreaInsets = safeAreaInsets
      self.traits = traits
      self.settling = settling
      self.tolerance = tolerance
      self.allowsUniformImage = allowsUniformImage
    }
  }

  extension SnapshotStrategy where Value: UIViewController {
    /// An image of the view controller's view, drawn through a window of the host application.
    public static func image(_ options: ViewImageOptions = ViewImageOptions()) -> SnapshotStrategy {
      let base = SnapshotStrategy<RenderedImage>.rendered(
        tolerance: options.tolerance, allowsUniformImage: options.allowsUniformImage)
      return SnapshotStrategy(
        pathExtension: base.pathExtension, validate: base.validate, compare: base.compare
      ) {
        viewController, configuration in
        let rendered = try await ViewRenderer.render(
          viewController, layout: options.layout, safeAreaInsets: options.safeAreaInsets,
          traits: options.traits, settling: options.settling)
        return try await base.encode(rendered, configuration)
      }
    }
  }

  extension SnapshotStrategy where Value: UIView {
    /// An image of the view, drawn through a window of the host application.
    public static func image(_ options: ViewImageOptions = ViewImageOptions()) -> SnapshotStrategy {
      SnapshotStrategy<UIViewController>.image(options).pullback { view in
        let viewController = UIViewController()
        viewController.view = view
        return viewController
      }
    }
  }

  extension SnapshotStrategy where Value: SwiftUI.View {
    /// An image of the view, drawn through a window of the host application.
    ///
    /// ```swift
    /// await expectSnapshot(
    ///   of: ProfileView(user: .sample),
    ///   as: .image(layout: .fixed(width: 390, height: 844), traits: { $0.userInterfaceStyle = .dark })
    /// )
    /// ```
    ///
    /// The view is drawn the way the screen shows it, including materials and effects that an
    /// off-screen rendering leaves out. That needs a host application for the test target.
    ///
    /// - Parameters:
    ///   - layout: The size the view is given.
    ///   - safeAreaInsets: The safe area the view sees.
    ///   - traits: Overrides traits, such as the interface style or the display scale.
    ///   - settling: When the view is ready.
    ///   - tolerance: How much the image may differ from its reference.
    ///   - allowsUniformImage: Whether an image of one flat colour is accepted.
    public static func image(
      layout: SnapshotLayout = .sizeThatFits,
      safeAreaInsets: UIEdgeInsets = .zero,
      traits: (@MainActor @Sendable (inout any UIMutableTraits) -> Void)? = nil,
      settling: SnapshotSettling = .immediately,
      tolerance: ImageTolerance? = nil,
      allowsUniformImage: Bool = false
    ) -> SnapshotStrategy {
      let options = ViewImageOptions(
        layout: layout, safeAreaInsets: safeAreaInsets, traits: traits, settling: settling,
        tolerance: tolerance, allowsUniformImage: allowsUniformImage)
      return SnapshotStrategy<UIViewController>.image(options).pullback { view in
        UIHostingController(rootView: view)
      }
    }
  }
#endif
