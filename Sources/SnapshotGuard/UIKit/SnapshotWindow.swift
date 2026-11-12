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
  import UIKit

  /// The size a view is given for its snapshot.
  public enum SnapshotLayout: Equatable, Sendable {
    /// The size the view asks for.
    case sizeThatFits
    /// A fixed size in points, such as the size of a device's screen.
    case fixed(width: CGFloat, height: CGFloat)
  }

  /// When a view is ready for its snapshot.
  public struct SnapshotSettling: Sendable {
    enum Storage: Sendable {
      case immediately
      case mainQueueDrained
      case delay(Duration)
      case condition(timeout: Duration, @MainActor @Sendable () -> Bool)
    }

    var storage: Storage

    /// As soon as the view has been laid out. This is the default: nothing that was scheduled
    /// for later gets to run first.
    public static let immediately = SnapshotSettling(storage: .immediately)

    /// Once the work that is already waiting on the main queue has run.
    ///
    /// State that arrives through `DispatchQueue.main.async` or `receive(on: DispatchQueue.main)`
    /// is applied before the snapshot. Spinning a run loop from the test does not do this: the
    /// main queue is not drained by a nested run loop.
    public static let mainQueueDrained = SnapshotSettling(storage: .mainQueueDrained)

    /// After a fixed time.
    public static func delay(_ duration: Duration) -> SnapshotSettling {
      SnapshotSettling(storage: .delay(duration))
    }

    /// Once a condition holds. The snapshot is taken anyway when the time runs out, so that the
    /// failure shows what the view looked like.
    public static func until(
      timeout: Duration = .seconds(5), _ condition: @escaping @MainActor @Sendable () -> Bool
    ) -> SnapshotSettling {
      SnapshotSettling(storage: .condition(timeout: timeout, condition))
    }

    @MainActor
    func wait() async {
      switch storage {
      case .immediately:
        break
      case .mainQueueDrained:
        await withCheckedContinuation { continuation in
          DispatchQueue.main.async { continuation.resume() }
        }
      case .delay(let duration):
        try? await Task.sleep(for: duration)
      case .condition(let timeout, let condition):
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
          try? await Task.sleep(for: .milliseconds(10))
        }
      }
    }
  }

  /// Thrown when a view cannot be rendered.
  public enum SnapshotRenderingError: Error, CustomStringConvertible, Sendable {
    /// There is no foreground scene to put a window in. Views are drawn through a real window,
    /// which needs a host application.
    case noHostApplication
    /// The view asked for no size.
    case emptySize

    public var description: String {
      switch self {
      case .noHostApplication:
        return "the view has no window to be drawn in. Image snapshots of views need a host "
          + "application: set one for the test target, or take the snapshot of a `CGImage` instead."
      case .emptySize:
        return "the view has no size. Give it one with `layout: .fixed(width:height:)`."
      }
    }
  }

  /// A window of the snapshot's size, in the host application's scene.
  ///
  /// The host application's own window is left alone. The window is opaque, so that nothing
  /// of the application behind it shows through a translucent view and into the snapshot.
  final class SnapshotWindow: UIWindow {
    init(windowScene: UIWindowScene, size: CGSize) {
      super.init(windowScene: windowScene)
      frame = CGRect(origin: .zero, size: size)
      backgroundColor = .black
      // Above the application's windows, so that the system composites this one.
      windowLevel = .alert + 1
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) is not supported")
    }
  }

  @MainActor
  enum ViewRenderer {
    /// Where the view is placed inside the window. Far outside the screen, it overlaps none of
    /// the areas the system insets content from, so the device the tests run on does not leak
    /// into the layout. The safe area the snapshot asks for is added on top.
    private static let offscreen: CGFloat = 10_000

    /// Shows a view controller in a window of its own, waits for it to settle and draws it.
    static func render(
      _ viewController: UIViewController,
      layout: SnapshotLayout,
      safeAreaInsets: UIEdgeInsets,
      traits: (@MainActor @Sendable (inout any UIMutableTraits) -> Void)?,
      settling: SnapshotSettling
    ) async throws -> RenderedImage {
      let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      guard
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
      else { throw SnapshotRenderingError.noHostApplication }

      let size: CGSize
      switch layout {
      case .fixed(let width, let height):
        size = CGSize(width: width, height: height)
      case .sizeThatFits:
        size = viewController.view.sizeThatFits(.zero)
      }
      guard size.width > 0, size.height > 0 else { throw SnapshotRenderingError.emptySize }

      let window = SnapshotWindow(windowScene: scene, size: size)
      if let traits {
        var overrides: any UIMutableTraits = window.traitOverrides
        traits(&overrides)
        if let overrides = overrides as? UITraitOverrides { window.traitOverrides = overrides }
      }

      let container = UIViewController()
      container.view.backgroundColor = .clear
      window.rootViewController = container
      window.isHidden = false

      let view: UIView = viewController.view
      container.addChild(viewController)
      view.frame = CGRect(origin: CGPoint(x: offscreen, y: offscreen), size: size)
      container.view.addSubview(view)
      viewController.didMove(toParent: container)
      viewController.additionalSafeAreaInsets = safeAreaInsets
      defer {
        viewController.willMove(toParent: nil)
        view.removeFromSuperview()
        viewController.removeFromParent()
        window.isHidden = true
        window.rootViewController = nil
        window.windowScene = nil
      }
      window.layoutIfNeeded()

      await settling.wait()
      window.layoutIfNeeded()

      let format = UIGraphicsImageRendererFormat(for: window.traitCollection)
      let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { _ in
        // Drawing through the window is what the screen shows. Rendering the layer off screen
        // leaves out materials and effects that only the compositor produces.
        view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
      }
      guard let cgImage = image.cgImage else { throw ImageEncodingError() }
      return RenderedImage(image: cgImage, scale: Double(image.scale))
    }
  }
#endif
