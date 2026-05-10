import SwiftUI

@MainActor
class GeneralSettingsViewModel: ObservableObject {
    @Published var language: String
    @Published var theme: String
    @Published var textSize: String
    @Published var ocrEnabled: Bool
    @Published var voiceShortcut: String

    init(
        language: String = "en",
        theme: String = "auto",
        textSize: String = "medium",
        ocrEnabled: Bool = GeneralSettingsStore.loadOCREnabled(),
        voiceShortcut: String = GeneralSettingsStore.loadVoiceShortcut()
    ) {
        self.language = language
        self.theme = theme
        self.textSize = textSize
        self.ocrEnabled = ocrEnabled
        self.voiceShortcut = voiceShortcut
    }

    func getConfig() -> (language: String, theme: String, textSize: String, ocrEnabled: Bool, voiceShortcut: String) {
        (language, theme, textSize, ocrEnabled, voiceShortcut)
    }
}

/// Tiny `UserDefaults`-backed store for general settings that don't live on
/// the agent config (OCR toggle, voice shortcut).
enum GeneralSettingsStore {
    private static let ocrEnabledKey = "settings.general.ocrEnabled"
    private static let voiceShortcutKey = "settings.general.voiceShortcut"
    private static let defaultVoiceShortcut = "Option"

    static func loadOCREnabled() -> Bool {
        let defaults = UserDefaults.standard
        // `object(forKey:)` distinguishes "never set" (default to true) from
        // "explicitly set to false" — `bool(forKey:)` alone would silently
        // return false on the first launch.
        if defaults.object(forKey: ocrEnabledKey) == nil { return true }
        return defaults.bool(forKey: ocrEnabledKey)
    }

    static func saveOCREnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: ocrEnabledKey)
    }

    static func loadVoiceShortcut() -> String {
        UserDefaults.standard.string(forKey: voiceShortcutKey) ?? defaultVoiceShortcut
    }

    static func saveVoiceShortcut(_ value: String) {
        UserDefaults.standard.set(value, forKey: voiceShortcutKey)
    }
}
