import SwiftUI

enum VoiceShortcut: String, CaseIterable, Identifiable {
    case option = "Option"
    case command = "Command"
    case control = "Control"
    case function = "Fn"

    var id: String { rawValue }

    init(storedValue: String) {
        self = VoiceShortcut(rawValue: storedValue) ?? .option
    }

    var modifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .option:
            return .option
        case .command:
            return .command
        case .control:
            return .control
        case .function:
            return .function
        }
    }

    func isPressed(in flags: NSEvent.ModifierFlags) -> Bool {
        flags
            .intersection(.deviceIndependentFlagsMask)
            .contains(modifierFlag)
    }
}

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
    static let ocrEnabledDidChangeNotification = Notification.Name("settings.general.ocrEnabled.didChange")

    private static let ocrEnabledKey = "settings.general.ocrEnabled"
    private static let voiceShortcutKey = "settings.general.voiceShortcut"
    private static let defaultVoiceShortcut = "Option"

    static func loadOCREnabled(defaults: UserDefaults = .standard) -> Bool {
        // `object(forKey:)` distinguishes "never set" from an explicit value.
        // Automatic OCR is opt-in, so first launch defaults to disabled.
        if defaults.object(forKey: ocrEnabledKey) == nil { return false }
        return defaults.bool(forKey: ocrEnabledKey)
    }

    static func saveOCREnabled(_ value: Bool, defaults: UserDefaults = .standard) {
        let oldValue = loadOCREnabled(defaults: defaults)
        defaults.set(value, forKey: ocrEnabledKey)

        guard oldValue != value else { return }
        NotificationCenter.default.post(
            name: ocrEnabledDidChangeNotification,
            object: nil,
            userInfo: ["enabled": value]
        )
    }

    static func loadVoiceShortcut(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: voiceShortcutKey) ?? defaultVoiceShortcut
    }

    static func saveVoiceShortcut(_ value: String, defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: voiceShortcutKey)
    }
}
