import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var viewModel: GeneralSettingsViewModel
    @StateObject private var permissions = ScreenCapturePermissionManager.shared

    private let contentWidth: CGFloat = 560
    private let menuControlWidth: CGFloat = 220
    private let segmentedControlWidth: CGFloat = 280
    
    var body: some View {
        SettingsCard(title: "settings.general.title") {
            VStack(alignment: .leading, spacing: 18) {
                languageSection
                themeSection
                textSizeSection
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

    private var textSizeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("settings.general.text_size")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            Picker("", selection: $viewModel.textSize) {
                Text("settings.general.text_size.small").tag("small")
                Text("settings.general.text_size.medium").tag("medium")
                Text("settings.general.text_size.large").tag("large")
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
            .onChange(of: viewModel.ocrEnabled) { _, newValue in
                if newValue {
                    Task { await permissions.requestPermissionIfNeeded() }
                }
            }

            if viewModel.ocrEnabled, permissions.isGranted == false {
                permissionBanner
            }
        }
        .task {
            guard viewModel.ocrEnabled else { return }
            await permissions.probe()
        }
    }

    private var permissionBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 14))
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 6) {
                Text("settings.general.screen_capture.missing_permission")
                    .font(.system(size: 12, weight: .semibold))
                Text("settings.general.screen_capture.missing_permission.description")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button("settings.general.screen_capture.open_settings") {
                        permissions.openSystemSettings()
                    }
                    .controlSize(.small)

                    Button("settings.general.screen_capture.recheck") {
                        Task { await permissions.probe() }
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.30), lineWidth: 1)
        )
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
