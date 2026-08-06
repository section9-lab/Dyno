import SwiftUI

@MainActor
final class GeneralSettingsViewModel: ObservableObject {
    @Published var language: String
    @Published var theme: String

    init(
        language: String = "en",
        theme: String = "auto"
    ) {
        self.language = language
        self.theme = theme
    }

    func getConfig() -> (language: String, theme: String) {
        (language, theme)
    }
}
