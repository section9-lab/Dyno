import SwiftUI

struct ModelProviderConfigView: View {
    @ObservedObject var agent: AgentManager
    @StateObject private var sandbox = SandboxAccessManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProviderId: String = ""
    @State private var draftApiKey: String = ""
    @State private var draftBaseURL: String = ""
    @State private var draftModelId: String = ""
    @State private var draftWorkspace: String = ""
    @State private var showAPIKey = false
    @State private var isDiscovering = false

    // Custom provider
    @State private var showCustomSheet = false
    @State private var customName = ""
    @State private var customBaseURL = ""
    @State private var customApiKey = ""

    private var currentProvider: Provider? {
        agent.registry.provider(for: selectedProviderId)
    }

    private var canSave: Bool {
        draftBaseURL.isNotBlank && draftModelId.isNotBlank && draftWorkspace.isNotBlank
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    statusCard
                    providerGrid
                    if !selectedProviderId.isEmpty {
                        connectionCard
                        modelPickerCard
                    }
                    workspaceCard
                    sandboxCard
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
            }
            .background(Color(red: 0.95, green: 0.95, blue: 0.96))
            .navigationTitle("模型设置")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存并连接") {
                        saveAndConnect()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                loadFromConfig()
            }
            .sheet(isPresented: $showCustomSheet) {
                addCustomProviderSheet
            }
        }
        .frame(minWidth: 640, minHeight: 520)
    }

    // MARK: - Status

    private var statusCard: some View {
        SettingsCard(title: "连接状态") {
            HStack(spacing: 8) {
                Circle()
                    .fill(agent.isServiceConnected ? .green : .orange)
                    .frame(width: 8, height: 8)
                Text(agent.connectionStatusText)
                    .foregroundColor(.secondary)
                Spacer()
                if agent.registry.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Provider Grid

    private var providerGrid: some View {
        SettingsCard(title: "模型提供商") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                ForEach(agent.registry.providers) { provider in
                    providerCard(provider)
                }
                addCustomCard
            }
        }
    }

    private func providerCard(_ provider: Provider) -> some View {
        Button {
            selectProvider(provider)
        } label: {
            VStack(spacing: 6) {
                Text(provider.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .foregroundColor(selectedProviderId == provider.id ? .white : .primary)

                if !provider.apiKey.isEmpty || provider.id == "ollama" {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(selectedProviderId == provider.id ? .white.opacity(0.8) : .green)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selectedProviderId == provider.id ? Color.accentColor : Color.white.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selectedProviderId == provider.id ? Color.accentColor : Color.black.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if provider.isCustom {
                Button("删除", role: .destructive) {
                    agent.registry.removeCustomProvider(provider.id)
                    if selectedProviderId == provider.id {
                        selectedProviderId = ""
                    }
                }
            }
        }
    }

    private var addCustomCard: some View {
        Button { showCustomSheet = true } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
                Text("自定义")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .foregroundColor(.secondary.opacity(0.4))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Connection

    private var connectionCard: some View {
        SettingsCard(title: "连接参数") {
            VStack(spacing: 10) {
                labeledTextField("Base URL", text: $draftBaseURL)

                HStack(spacing: 10) {
                    Group {
                        if showAPIKey {
                            TextField("API Key（Ollama 可为空）", text: $draftApiKey)
                        } else {
                            SecureField("API Key（Ollama 可为空）", text: $draftApiKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)

                    Button {
                        showAPIKey.toggle()
                    } label: {
                        Image(systemName: showAPIKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }

                if let provider = currentProvider, !provider.envKeys.isEmpty {
                    Text("环境变量：\(provider.envKeys.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack {
                    Spacer()
                    Button("检测连接并发现模型") {
                        discoverModels()
                    }
                    .disabled(isDiscovering)
                }
            }
        }
    }

    // MARK: - Model Picker

    private var modelPickerCard: some View {
        SettingsCard(title: "选择模型") {
            let models = currentProvider?.models ?? []

            if models.isEmpty {
                Text("点击「检测连接并发现模型」获取可用模型列表")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                labeledTextField("或手动输入模型名", text: $draftModelId)
            } else {
                VStack(spacing: 0) {
                    let liveModels = models.filter(\.isLive)
                    let catalogModels = models.filter { !$0.isLive }

                    if !liveModels.isEmpty {
                        modelSection(title: "可用模型（\(liveModels.count)）", models: liveModels, live: true)
                    }

                    if !catalogModels.isEmpty {
                        modelSection(title: "目录模型", models: catalogModels, live: false)
                    }
                }
                .frame(maxHeight: 240)
            }
        }
    }

    private func modelSection(title: String, models: [ModelInfo], live: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
                .padding(.top, 6)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(models) { model in
                        Button {
                            draftModelId = model.id
                        } label: {
                            HStack(spacing: 8) {
                                if live {
                                    Circle().fill(.green).frame(width: 6, height: 6)
                                } else {
                                    Circle().fill(.gray.opacity(0.3)).frame(width: 6, height: 6)
                                }

                                Text(model.name)
                                    .font(.system(size: 13))
                                    .foregroundColor(live ? .primary : .secondary)
                                    .lineLimit(1)

                                Spacer()

                                if model.reasoning {
                                    Text("推理")
                                        .font(.system(size: 9))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.purple.opacity(0.1))
                                        .foregroundColor(.purple)
                                        .clipShape(Capsule())
                                }

                                if let ctx = model.contextWindow {
                                    Text("\(ctx / 1000)K")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }

                                if model.id == draftModelId {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(model.id == draftModelId ? Color.accentColor.opacity(0.1) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Workspace

    private var workspaceCard: some View {
        SettingsCard(title: "Workspace") {
            labeledTextField("工作目录", text: $draftWorkspace)
            HStack {
                Button("测试读写权限") {
                    Task { await agent.verifyWorkspaceAccess() }
                }
                if !agent.workspaceCheckMessage.isEmpty {
                    Text(agent.workspaceCheckMessage)
                        .font(.caption)
                        .foregroundColor(agent.workspaceCheckMessage.hasPrefix("✅") ? .green : .secondary)
                        .lineLimit(2)
                }
                Spacer()
            }
        }
    }

    // MARK: - Sandbox

    private var sandboxCard: some View {
        SettingsCard(title: "沙箱权限") {
            VStack(spacing: 10) {
                if sandbox.entries.isEmpty {
                    Text("未授权任何外部目录。当前仅保证 Workspace 目录内访问。")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 8) {
                        ForEach(sandbox.entries) { entry in
                            let status = sandbox.status(of: entry)
                            HStack {
                                Text(entry.path)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text(statusLabel(for: status))
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(statusColor(for: status).opacity(0.15))
                                    .foregroundColor(statusColor(for: status))
                                    .clipShape(Capsule())
                                if status != .active {
                                    Button("重新授权") {
                                        sandbox.reauthorizeEntry(entry)
                                        agent.refreshRuntimeContext()
                                    }
                                    .buttonStyle(.borderless)
                                }
                                Button(role: .destructive) {
                                    sandbox.removeEntry(entry)
                                    agent.refreshRuntimeContext()
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                HStack {
                    Button("添加目录授权...") {
                        sandbox.authorizeDirectoryViaOpenPanel()
                        agent.refreshRuntimeContext()
                    }
                    Button("刷新授权") {
                        sandbox.refreshAccess()
                        agent.refreshRuntimeContext()
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Custom Provider Sheet

    private var addCustomProviderSheet: some View {
        VStack(spacing: 16) {
            Text("添加自定义提供商")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                labeledTextField("名称", text: $customName)
                labeledTextField("Base URL", text: $customBaseURL)
                labeledTextField("API Key（可选）", text: $customApiKey)
            }

            HStack {
                Button("取消") { showCustomSheet = false }
                Spacer()
                Button("添加") {
                    let name = customName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let url = customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty, !url.isEmpty else { return }
                    agent.registry.addCustomProvider(name: name, baseURL: url, apiKey: customApiKey)
                    customName = ""
                    customBaseURL = ""
                    customApiKey = ""
                    showCustomSheet = false
                }
                .disabled(!customName.isNotBlank || !customBaseURL.isNotBlank)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    // MARK: - Actions

    private func loadFromConfig() {
        selectedProviderId = agent.config.providerId
        draftBaseURL = agent.config.baseURL
        draftApiKey = agent.config.apiKey
        draftModelId = agent.config.modelId
        draftWorkspace = agent.config.workspace
    }

    private func selectProvider(_ provider: Provider) {
        selectedProviderId = provider.id
        draftBaseURL = provider.baseURL
        draftApiKey = provider.apiKey

        // Pick first live model or first catalog model
        let firstLive = provider.models.first(where: \.isLive)
        let firstModel = firstLive ?? provider.models.first
        draftModelId = firstModel?.id ?? ""

        // Auto-discover models
        discoverModels()
    }

    private func discoverModels() {
        isDiscovering = true
        // Sync current API key to registry before discovering
        agent.registry.setApiKey(draftApiKey, for: selectedProviderId)

        // Update baseURL in registry if changed
        if let idx = agent.registry.providers.firstIndex(where: { $0.id == selectedProviderId }) {
            agent.registry.providers[idx].baseURL = draftBaseURL
        }

        Task {
            await agent.registry.discoverLiveModels(for: selectedProviderId)
            isDiscovering = false

            // Auto-select first live model if none selected
            if draftModelId.isEmpty,
               let provider = agent.registry.provider(for: selectedProviderId),
               let first = provider.models.first(where: \.isLive) {
                draftModelId = first.id
            }
        }
    }

    private func saveAndConnect() {
        let newConfig = AgentServiceConfig(
            providerId: selectedProviderId,
            baseURL: draftBaseURL,
            apiKey: draftApiKey,
            modelId: draftModelId,
            workspace: draftWorkspace
        )
        Task {
            await agent.applyConfig(newConfig)
            dismiss()
        }
    }

    // MARK: - Helpers

    private func labeledTextField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func statusLabel(for status: SandboxAuthorizationStatus) -> String {
        switch status {
        case .active: return "已授权"
        case .stale: return "需更新"
        case .invalid: return "无效"
        }
    }

    private func statusColor(for status: SandboxAuthorizationStatus) -> Color {
        switch status {
        case .active: return .green
        case .stale: return .orange
        case .invalid: return .red
        }
    }
}
