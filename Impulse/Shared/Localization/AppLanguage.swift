import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case en
    case zh
    case es
    case fr
    case ru
    case ja

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .en: return "English"
        case .zh: return "中文"
        case .es: return "Español"
        case .fr: return "Français"
        case .ru: return "Русский"
        case .ja: return "日本語"
        }
    }

    var speechLocaleIdentifier: String {
        switch self {
        case .en: return "en-US"
        case .zh: return "zh-Hans"
        case .es: return "es-ES"
        case .fr: return "fr-FR"
        case .ru: return "ru-RU"
        case .ja: return "ja-JP"
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case auto
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .auto: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AppTextSize: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    /// Multiplier applied to base font sizes used by chat views. The spread
    /// (~0.92 / 1.0 / 1.14) is wide enough to be visible without breaking
    /// existing layouts that rely on row heights / line wrapping.
    var multiplier: CGFloat {
        switch self {
        case .small:  return 0.92
        case .medium: return 1.0
        case .large:  return 1.14
        }
    }
}

@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    private static let themeKey = "app.theme"
    private static let textSizeKey = "app.textSize"

    @Published var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: Self.themeKey)
        }
    }

    @Published var textSize: AppTextSize {
        didSet {
            UserDefaults.standard.set(textSize.rawValue, forKey: Self.textSizeKey)
        }
    }

    private init() {
        let storedTheme = UserDefaults.standard.string(forKey: Self.themeKey)
        self.theme = storedTheme.flatMap(AppTheme.init(rawValue:)) ?? .auto

        let storedSize = UserDefaults.standard.string(forKey: Self.textSizeKey)
        self.textSize = storedSize.flatMap(AppTextSize.init(rawValue:)) ?? .medium
    }
}

@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    private static let storageKey = "app.language"

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
        }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.storageKey)
        self.language = stored.flatMap(AppLanguage.init(rawValue:)) ?? .en
    }

    var locale: Locale {
        Locale(identifier: language.rawValue)
    }
}

enum L10n {
    static func tr(_ key: String, _ arguments: CVarArg...) -> String {
        let language = UserDefaults.standard.string(forKey: "app.language")
            .flatMap(AppLanguage.init(rawValue:))?
            .rawValue ?? AppLanguage.en.rawValue

        let bundle = resolvedBundle(for: language)
        var format = NSLocalizedString(key, bundle: bundle, comment: "")

        // If key not found in preferred language, fall back to English
        if format == key, language != AppLanguage.en.rawValue,
           let enBundle = resolvedBundle(language: AppLanguage.en.rawValue) {
            let enFormat = NSLocalizedString(key, bundle: enBundle, comment: "")
            if enFormat != key { format = enFormat }
        }

        if arguments.isEmpty { return format }
        return String(format: format, locale: Locale(identifier: language), arguments: arguments)
    }

    private static func resolvedBundle(for language: String) -> Bundle {
        resolvedBundle(language: language) ?? .main
    }

    private static func resolvedBundle(language: String) -> Bundle? {
        Bundle.main.path(forResource: language, ofType: "lproj")
            .flatMap(Bundle.init(path:))
    }
}
