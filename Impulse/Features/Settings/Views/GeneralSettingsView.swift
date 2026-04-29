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
                ocrSection
                voiceSection
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
    
    private var ocrSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("settings.general.screen_capture")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            
            Toggle(isOn: $viewModel.ocrEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("settings.general.auto_ocr")
                    Text("settings.general.auto_ocr.description")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
    }
    
    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("settings.general.voice_shortcut")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            
            Picker("", selection: $viewModel.voiceShortcut) {
                Text("Option (⌥)").tag("Option")
                Text("Command (⌘)").tag("Command")
                Text("Control (⌃)").tag("Control")
                Text("Fn").tag("Fn")
            }
            .pickerStyle(.menu)
            .frame(width: menuControlWidth, alignment: .leading)
            
            Text("settings.general.voice_shortcut.description")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    GeneralSettingsView(viewModel: GeneralSettingsViewModel())
        .frame(width: 600)
}
