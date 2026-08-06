import SwiftUI

struct SettingsContainerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localization: LocalizationManager
    @EnvironmentObject private var themeManager: ThemeManager

    @State private var selectedTab: SettingsTab = .general
    @StateObject private var generalSettings = GeneralSettingsViewModel(
        language: LocalizationManager.shared.language.rawValue,
        theme: ThemeManager.shared.theme.rawValue
    )

    enum SettingsTab: CaseIterable, Identifiable {
        case general
        case diagnostics

        var id: Self { self }

        var titleKey: LocalizedStringKey {
            switch self {
            case .general: return "settings.tab.general"
            case .diagnostics: return "settings.tab.diagnostics"
            }
        }

        var icon: String {
            switch self {
            case .general: return "gear"
            case .diagnostics: return "stethoscope"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailContent
        }
        .environment(\.locale, localization.locale)
        .id(localization.language)
        .frame(width: 800, height: 640)
        .onChange(of: generalSettings.language) { newValue in
            guard let language = AppLanguage(rawValue: newValue) else { return }
            localization.language = language
        }
        .onChange(of: generalSettings.theme) { newValue in
            guard let theme = AppTheme(rawValue: newValue) else { return }
            themeManager.theme = theme
        }
    }

    private var sidebar: some View {
        List(SettingsTab.allCases, selection: $selectedTab) { tab in
            Label(tab.titleKey, systemImage: tab.icon)
                .tag(tab)
        }
        .listStyle(.sidebar)
        .frame(minWidth: 150)
    }

    private var detailContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sectionContainer(.general, title: "settings.general.title") {
                        GeneralSettingsView(viewModel: generalSettings)
                    }

                    sectionContainer(.diagnostics, title: "settings.diagnostics.title") {
                        DiagnosticsSettingsView()
                    }
                }
                .padding(20)
                .frame(maxWidth: 900, alignment: .leading)
            }
            .navigationTitle("settings.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") { saveSettings() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .onChange(of: selectedTab) { tab in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(tab, anchor: .top)
                }
            }
        }
    }

    private func sectionContainer<Content: View>(
        _ tab: SettingsTab,
        title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
            content()
        }
        .id(tab)
    }

    private func saveSettings() {
        let generalConfig = generalSettings.getConfig()

        if let theme = AppTheme(rawValue: generalConfig.theme) {
            themeManager.theme = theme
        }
        if let language = AppLanguage(rawValue: generalConfig.language) {
            localization.language = language
        }

        dismiss()
    }
}

#Preview {
    SettingsContainerView()
}
