#if os(iOS) || os(tvOS)
  import SnapshotTesting
  import SwiftUI
  import UIKit

  extension Snapshotting where Value: SwiftUI.View, Format == UIImage {
    /// A snapshot strategy that renders a SwiftUI view through the host application's key
    /// window and compares it without perceptual matching.
    ///
    /// Two defaults differ from `.image`:
    ///
    /// - The view is drawn with `drawHierarchyInKeyWindow`. The default off-screen path
    ///   (`layer.render(in:)`) draws nothing for `glassEffect` on recent iOS versions, so a
    ///   screen built from glass comes out blank. This requires a host application.
    /// - `perceptualPrecision` is fixed to `1`. A lower value switches the library to a
    ///   comparison that ignores colour management, which can report a large difference for
    ///   two images that are visually identical when one was captured from a wide-gamut window
    ///   and the other was loaded from an sRGB PNG. Express tolerance with `precision` instead.
    ///
    /// - Parameters:
    ///   - precision: The share of pixels that must match, from `0` to `1`. The default allows
    ///     0.2% of pixels to differ, which absorbs a spinner or a marquee caught mid-animation.
    ///   - layout: The size to render the view at.
    ///   - traits: The traits to render the view with.
    public static func keyWindowImage(
      precision: Float = 0.998,
      layout: SwiftUISnapshotLayout = .sizeThatFits,
      traits: UITraitCollection = .init()
    ) -> Snapshotting {
      .image(
        drawHierarchyInKeyWindow: true,
        precision: precision,
        perceptualPrecision: 1,
        layout: layout,
        traits: traits
      )
    }
  }
#endif
