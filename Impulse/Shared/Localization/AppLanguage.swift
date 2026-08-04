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

@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    private static let themeKey = "app.theme"

    @Published var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: Self.themeKey)
        }
    }

    private init() {
        let storedTheme = UserDefaults.standard.string(forKey: Self.themeKey)
        self.theme = storedTheme.flatMap(AppTheme.init(rawValue:)) ?? .auto
    }
}

@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    private static let storageKey = "app.language"

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
            Self.applyAppleLanguagesOverride(language)
        }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.storageKey)
        let resolved = stored.flatMap(AppLanguage.init(rawValue:)) ?? .en
        self.language = resolved
        Self.applyAppleLanguagesOverride(resolved)
    }

    var locale: Locale {
        Locale(identifier: language.rawValue)
    }

    private static func applyAppleLanguagesOverride(_ language: AppLanguage) {
        UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
    }
}

enum L10n {
    static func tr(_ key: String, _ arguments: CVarArg...) -> String {
        let language = UserDefaults.standard.string(forKey: "app.language")
            .flatMap(AppLanguage.init(rawValue:))?
            .rawValue ?? AppLanguage.en.rawValue

        let bundle = resolvedBundle(for: language)
        var format = NSLocalizedString(key, bundle: bundle, comment: "")

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
