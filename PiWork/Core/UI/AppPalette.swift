import AppKit
import SwiftUI

/// Appearance-aware surfaces for the app's hand-built chrome.
///
/// The design is a custom gradient rather than system materials, so these
/// can't come from `NSColor`'s semantic set — but they still have to follow
/// the effective appearance now that the theme is user-selectable. Each one
/// is a dynamic `NSColor`, which resolves at draw time against the color
/// scheme in the environment, including one forced by
/// `.preferredColorScheme`.
enum AppPalette {
    /// Window backdrop: near-white washing into sky blue in light, deep
    /// slate washing into midnight blue in dark. The axis is mostly vertical
    /// with a slight trailing bias, keeping both top corners pale and
    /// concentrating the color in the lower half.
    static let windowGradient = LinearGradient(
        stops: [
            .init(color: dynamic(light: 0xF6F8FA, dark: 0x1B1F26), location: 0.00),
            .init(color: dynamic(light: 0xEDF2FA, dark: 0x191F28), location: 0.35),
            .init(color: dynamic(light: 0xC9DEF5, dark: 0x17273A), location: 0.70),
            .init(color: dynamic(light: 0x7DB3E8, dark: 0x143050), location: 1.00)
        ],
        startPoint: UnitPoint(x: 0.15, y: 0.0),
        endPoint: UnitPoint(x: 0.95, y: 1.0)
    )

    /// The floating sidebar panel, a touch lighter than the content area at
    /// the same height so it reads as sitting above it.
    static let sidebarSurface = LinearGradient(
        colors: [
            dynamic(light: 0xF8F9FA, dark: 0x272C34),
            dynamic(light: 0xDEEFFB, dark: 0x22303F)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Hairline highlight around the sidebar panel.
    static let panelBorder = dynamic(
        light: 0xFFFFFF, lightAlpha: 0.55,
        dark: 0xFFFFFF, darkAlpha: 0.09
    )

    /// Opaque raised card — input pills, the sidebar toggle, the selected
    /// segmented tab.
    static let raisedSurface = dynamic(light: 0xFFFFFF, dark: 0x2E343D)

    /// Semi-transparent raised card — the beta badge and chat bubbles, which
    /// let a little of the backdrop through.
    static let translucentSurface = dynamic(
        light: 0xFFFFFF, lightAlpha: 0.88,
        dark: 0x2E343D, darkAlpha: 0.88
    )

    /// Fill behind the selected sidebar folder row.
    static let selectedRowFill = dynamic(
        light: 0xFFFFFF, lightAlpha: 0.75,
        dark: 0xFFFFFF, darkAlpha: 0.10
    )

    /// Fill behind a hovered (not selected) sidebar row — a lighter step
    /// below `selectedRowFill` so hover and selected read as two distinct
    /// states rather than the same highlight.
    static let hoverRowFill = dynamic(
        light: 0xFFFFFF, lightAlpha: 0.40,
        dark: 0xFFFFFF, darkAlpha: 0.06
    )

    /// Track behind the sidebar's segmented tab control.
    static let segmentedTrack = dynamic(
        light: 0x000000, lightAlpha: 0.05,
        dark: 0x000000, darkAlpha: 0.22
    )

    /// Leading accent bar on the welcome screen's suggestion rows.
    static let accentBar = dynamic(light: 0x8FB0EB, dark: 0x5E86C9)

    /// Drop shadow under raised cards. Dark mode needs a much heavier shadow
    /// for the same sense of elevation.
    static let raisedShadow = dynamic(
        light: 0x000000, lightAlpha: 0.10,
        dark: 0x000000, darkAlpha: 0.45
    )

    /// Softer variant for small elements (chat bubbles, the toggle button).
    static let subtleShadow = dynamic(
        light: 0x000000, lightAlpha: 0.08,
        dark: 0x000000, darkAlpha: 0.35
    )

    private static func dynamic(
        light: UInt32,
        lightAlpha: Double = 1,
        dark: UInt32,
        darkAlpha: Double = 1
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: CGFloat(isDark ? darkAlpha : lightAlpha)
            )
        })
    }
}
