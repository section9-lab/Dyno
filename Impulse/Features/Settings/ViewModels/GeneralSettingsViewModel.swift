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
        ocrEnabled: Bool = true,
        voiceShortcut: String = "Option"
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
