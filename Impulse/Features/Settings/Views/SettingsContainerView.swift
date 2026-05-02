import SwiftUI

struct SettingsContainerView: View {
    let agent: AgentManager
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localization: LocalizationManager
    @EnvironmentObject private var themeManager: ThemeManager

    @State private var selectedTab: SettingsTab = .general

    enum SettingsTab: CaseIterable, Identifiable {
        case general
        case model
        case sandbox
        case diagnostics

        var id: Self { self }

        var titleKey: LocalizedStringKey {
            switch self {
            case .general: return "settings.tab.general"
            case .model: return "settings.tab.model"
            case .sandbox: return "settings.tab.files"
            case .diagnostics: return "settings.tab.diagnostics"
            }
        }

        var icon: String {
            switch self {
            case .general: return "gear"
            case .model: return "cpu"
            case .sandbox: return "folder.badge.gear"
            case .diagnostics: return "stethoscope"
            }
        }
    }

    // References to child views for collecting config
    @StateObject private var generalSettings: GeneralSettingsViewModel
    @StateObject private var modelSettings: ModelSettingsViewModel
    @StateObject private var sandboxSettings: SandboxSettingsViewModel

    init(agent: AgentManager) {
        self.agent = agent
        let config = agent.config

        _generalSettings = StateObject(wrappedValue: GeneralSettingsViewModel(
            language: LocalizationManager.shared.language.rawValue,
            theme: ThemeManager.shared.theme.rawValue,
            textSize: ThemeManager.shared.textSize.rawValue,
            ocrEnabled: true,
            voiceShortcut: "Option"
        ))

        _modelSettings = StateObject(wrappedValue: ModelSettingsViewModel(
            selectedProviderId: config.providerId,
            draftApiKey: config.apiKey,
            draftBaseURL: config.baseURL,
            draftModelId: config.modelId
        ))

        _sandboxSettings = StateObject(wrappedValue: SandboxSettingsViewModel())
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
        .task {
            await agent.refreshServiceStatus()
        }
        .onChange(of: generalSettings.language) { _, newValue in
            guard let language = AppLanguage(rawValue: newValue) else { return }
            localization.language = language
        }
        .onChange(of: generalSettings.theme) { _, newValue in
            guard let theme = AppTheme(rawValue: newValue) else { return }
            themeManager.theme = theme
        }
        .onChange(of: generalSettings.textSize) { _, newValue in
            guard let size = AppTextSize(rawValue: newValue) else { return }
            themeManager.textSize = size
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

                    sectionContainer(.model, title: "settings.model.title") {
                        ModelSettingsView(agent: agent, viewModel: modelSettings)
                    }

                    sectionContainer(.sandbox, title: "settings.files.title") {
                        SandboxSettingsView(agent: agent, viewModel: sandboxSettings)
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
            .onChange(of: selectedTab) { _, tab in
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
        let modelConfig = modelSettings.getConfig()

        var newConfig = agent.config
        if let theme = AppTheme(rawValue: generalConfig.theme) {
            themeManager.theme = theme
        }
        if let size = AppTextSize(rawValue: generalConfig.textSize) {
            themeManager.textSize = size
        }

        if let model = modelConfig {
            newConfig.providerId = model.providerId
            newConfig.baseURL = model.baseURL
            newConfig.apiKey = model.apiKey
            newConfig.modelId = model.modelId
        }

        Task {
            await agent.applyConfig(newConfig)
            dismiss()
        }
    }
}

#Preview {
    SettingsContainerView(agent: AgentManager.shared)
}
