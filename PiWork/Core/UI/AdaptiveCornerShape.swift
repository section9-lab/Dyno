import SwiftUI

/// Returns a rounded-rectangle shape. On macOS 26 this is meant to render the
/// system's native smooth (concentric) corner style, falling back to a
/// standard continuous-style rounded rectangle on macOS 13-25.
///
/// NOTE: `ConcentricRectangle` (the macOS 26 API for this) is only declared
/// in the macOS 26 SDK, so referencing it here would fail to compile on
/// older Xcode toolchains regardless of `#available` guards. Once building
/// with Xcode 26+, swap the body below for:
///
///   if #available(macOS 26, *) {
///       return AnyShape(ConcentricRectangle(corners: RectangleCornerRadii(
///           topLeading: cornerRadius, bottomLeading: cornerRadius,
///           bottomTrailing: cornerRadius, topTrailing: cornerRadius
///       )))
///   } else {
///       return AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
///   }
func adaptiveRoundedShape(cornerRadius: CGFloat) -> AnyShape {
    AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
}

extension View {
    /// Clips this view with an adaptive rounded-rectangle shape. See
    /// `adaptiveRoundedShape(cornerRadius:)` for the macOS 26 upgrade path.
    func adaptiveCornerRadius(_ radius: CGFloat) -> some View {
        clipShape(adaptiveRoundedShape(cornerRadius: radius))
    }
}
