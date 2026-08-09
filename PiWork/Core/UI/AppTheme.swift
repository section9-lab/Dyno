import SwiftUI

/// User-selectable appearance. `system` defers to the OS setting; the other
/// two pin the app regardless of it.
enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return L10n.string("theme.system")
        case .light: return L10n.string("theme.light")
        case .dark: return L10n.string("theme.dark")
        }
    }

    var icon: String {
        switch self {
        case .system: return "desktopcomputer"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    /// `nil` hands control back to the system appearance.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Holds the appearance choice and persists it so it survives relaunch.
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()

    private static let defaultsKey = "appearance.theme"

    @Published var theme: AppTheme {
        didSet {
            guard theme != oldValue else { return }
            UserDefaults.standard.set(theme.rawValue, forKey: Self.defaultsKey)
        }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.defaultsKey)
        theme = stored.flatMap(AppTheme.init(rawValue:)) ?? .system
    }
}

struct RoundedInteractionVisualState: Equatable {
    let isHovering: Bool
    let isPressed: Bool

    var overlayOpacity: Double {
        if isPressed { return 0.10 }
        return isHovering ? 0.055 : 0
    }

    var scale: CGFloat { isPressed ? 0.985 : 1 }
}

/// Shared pointer and press feedback for the app's custom rounded controls.
/// The label owns its layout; this style only supplies the interaction layer.
struct RoundedInteractionButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 10
    var isSelected = false
    var baseFill = Color.clear

    func makeBody(configuration: Configuration) -> some View {
        RoundedInteractionButtonBody(
            configuration: configuration,
            cornerRadius: cornerRadius,
            isSelected: isSelected,
            baseFill: baseFill
        )
    }
}

private struct RoundedInteractionButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let cornerRadius: CGFloat
    let isSelected: Bool
    let baseFill: Color

    @State private var isHovering = false

    private var visualState: RoundedInteractionVisualState {
        RoundedInteractionVisualState(
            isHovering: isHovering,
            isPressed: configuration.isPressed
        )
    }

    var body: some View {
        configuration.label
            .background(
                adaptiveRoundedShape(cornerRadius: cornerRadius)
                    .fill(isSelected ? AppPalette.selectedRowFill : baseFill)
            )
            .overlay(
                adaptiveRoundedShape(cornerRadius: cornerRadius)
                    .fill(Color.primary.opacity(visualState.overlayOpacity))
            )
            .contentShape(adaptiveRoundedShape(cornerRadius: cornerRadius))
            .scaleEffect(visualState.scale)
            .animation(.easeOut(duration: 0.1), value: visualState)
            .onHover { isHovering = $0 }
    }
}
