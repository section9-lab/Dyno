import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var viewModel: GeneralSettingsViewModel

    private let contentWidth: CGFloat = 560
    private let menuControlWidth: CGFloat = 220
    private let segmentedControlWidth: CGFloat = 280

    var body: some View {
        SettingsCard(title: "settings.general.title") {
            VStack(alignment: .leading, spacing: 18) {
                languageSection
                themeSection
            }
            .frame(width: contentWidth, alignment: .leading)
        }
    }

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("settings.general.language")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            Picker("", selection: $viewModel.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language.rawValue)
                }
            }
            .pickerStyle(.menu)
            .frame(width: menuControlWidth, alignment: .leading)
        }
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("settings.general.theme")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            Picker("", selection: $viewModel.theme) {
                Text("settings.general.theme.auto").tag("auto")
                Text("settings.general.theme.light").tag("light")
                Text("settings.general.theme.dark").tag("dark")
            }
            .pickerStyle(.segmented)
            .frame(width: segmentedControlWidth, alignment: .leading)
        }
    }
}

#Preview {
    GeneralSettingsView(viewModel: GeneralSettingsViewModel())
        .frame(width: 600)
}
