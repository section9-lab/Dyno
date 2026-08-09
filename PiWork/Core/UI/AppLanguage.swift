import Combine
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case spanish = "es"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .spanish: return "Español"
        }
    }

    var locale: Locale { Locale(identifier: rawValue) }
}

final class LanguageStore: ObservableObject {
    static let shared = LanguageStore()

    private static let defaultKey = "app.language"
    private let defaults: UserDefaults
    private let defaultsKey: String

    @Published var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            defaults.set(language.rawValue, forKey: defaultsKey)
        }
    }

    init(
        defaults: UserDefaults = .standard,
        defaultsKey: String = LanguageStore.defaultKey
    ) {
        self.defaults = defaults
        self.defaultsKey = defaultsKey
        language = defaults.string(forKey: defaultsKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? .english
    }
}

enum L10n {
    static var currentLanguage: AppLanguage { storedLanguage }

    static func string(
        _ key: String,
        language: AppLanguage? = nil
    ) -> String {
        let selectedLanguage = language ?? storedLanguage
        let localized = bundle(for: selectedLanguage)?
            .localizedString(forKey: key, value: nil, table: nil) ?? key
        guard localized == key, selectedLanguage != .english else { return localized }
        return bundle(for: .english)?
            .localizedString(forKey: key, value: key, table: nil) ?? key
    }

    static func format(
        _ key: String,
        language: AppLanguage? = nil,
        _ arguments: CVarArg...
    ) -> String {
        let selectedLanguage = language ?? storedLanguage
        return String(
            format: string(key, language: selectedLanguage),
            locale: selectedLanguage.locale,
            arguments: arguments
        )
    }

    private static var storedLanguage: AppLanguage {
        UserDefaults.standard.string(forKey: "app.language")
            .flatMap(AppLanguage.init(rawValue:)) ?? .english
    }

    private static func bundle(for language: AppLanguage) -> Bundle? {
        guard let path = Bundle.main.path(
            forResource: language.rawValue,
            ofType: "lproj"
        ) else { return nil }
        return Bundle(path: path)
    }
}
