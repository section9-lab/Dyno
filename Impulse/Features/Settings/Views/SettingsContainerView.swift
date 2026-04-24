import SwiftUI

struct SettingsContainerView: View {
    let agent: AgentManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: SettingsTab = .general

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "通用"
        case model = "模型"
        case sandbox = "文件"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general: return "gear"
            case .model: return "cpu"
            case .sandbox: return "folder.badge.gear"
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
            language: "zh",
            theme: "auto",
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
        .frame(minWidth: 800, minHeight: 600)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    saveSettings()
                }
            }
        }
    }
    
    private var sidebar: some View {
        List(SettingsTab.allCases, selection: $selectedTab) { tab in
            Label(tab.rawValue, systemImage: tab.icon)
                .tag(tab)
        }
        .listStyle(.sidebar)
        .frame(minWidth: 150)
    }
    
    private var detailContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sectionContainer(.general, title: "通用设置") {
                        GeneralSettingsView(viewModel: generalSettings)
                    }

                    sectionContainer(.model, title: "模型设置") {
                        ModelSettingsView(agent: agent, viewModel: modelSettings)
                    }

                    sectionContainer(.sandbox, title: "文件设置") {
                        SandboxSettingsView(agent: agent, viewModel: sandboxSettings)
                    }
                }
                .padding(20)
                .frame(maxWidth: 900, alignment: .leading)
            }
            .navigationTitle("设置")
            .onChange(of: selectedTab) { tab in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(tab, anchor: .top)
                }
            }
        }
    }

    private func sectionContainer<Content: View>(
        _ tab: SettingsTab,
        title: String,
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
        let _ = generalSettings.getConfig()
        let modelConfig = modelSettings.getConfig()

        var newConfig = agent.config

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
