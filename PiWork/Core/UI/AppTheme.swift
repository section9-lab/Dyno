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
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
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
