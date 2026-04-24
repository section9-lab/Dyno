import SwiftUI

struct ModelSettingsView: View {
    @ObservedObject var agent: AgentManager
    @ObservedObject var viewModel: ModelSettingsViewModel
    
    private var currentProvider: Provider? {
        agent.registry.provider(for: viewModel.selectedProviderId)
    }
    
    var body: some View {
        SettingsCard(title: "模型连接") {
            VStack(alignment: .leading, spacing: 14) {
                connectionStatusRow
                
                Divider()
                
                providerSection
                
                if !viewModel.selectedProviderId.isEmpty {
                    Divider()
                    connectionFieldsSection
                    
                    Divider()
                    modelPickerSection
                }
            }
        }
        .sheet(isPresented: $viewModel.showCustomSheet) {
            addCustomProviderSheet
        }
    }
    
    private var connectionStatusRow: some View {
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
    
    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("模型提供商")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            Picker("选择提供商", selection: $viewModel.selectedProviderId) {
                ForEach(agent.registry.providers) { provider in
                    Text(provider.name).tag(provider.id)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: viewModel.selectedProviderId) { _, newValue in
                guard let provider = agent.registry.provider(for: newValue) else { return }
                selectProvider(provider)
            }

            HStack(spacing: 10) {
                Button("添加自定义提供商") {
                    viewModel.showCustomSheet = true
                }
                .buttonStyle(.bordered)

                if let provider = currentProvider, provider.isCustom {
                    Button("删除当前自定义提供商", role: .destructive) {
                        agent.registry.removeCustomProvider(provider.id)
                        if let fallback = agent.registry.providers.first {
                            selectProvider(fallback)
                        } else {
                            viewModel.selectedProviderId = ""
                            viewModel.draftBaseURL = ""
                            viewModel.draftApiKey = ""
                            viewModel.draftModelId = ""
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
    
    private var connectionFieldsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("连接参数")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            
            VStack(spacing: 10) {
                labeledTextField("Base URL", text: $viewModel.draftBaseURL)
                
                HStack(spacing: 10) {
                    Group {
                        if viewModel.showAPIKey {
                            TextField("API Key（Ollama 可为空）", text: $viewModel.draftApiKey)
                        } else {
                            SecureField("API Key（Ollama 可为空）", text: $viewModel.draftApiKey)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    
                    Button {
                        viewModel.showAPIKey.toggle()
                    } label: {
                        Image(systemName: viewModel.showAPIKey ? "eye.slash" : "eye")
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
                    .disabled(viewModel.isDiscovering)
                }
            }
        }
    }
    
    private var modelPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("选择模型")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            
            Group {
                let models = currentProvider?.models ?? []
                if models.isEmpty {
                    Text("点击「检测连接并发现模型」获取可用模型列表")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    labeledTextField("或手动输入模型名", text: $viewModel.draftModelId)
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
                            viewModel.draftModelId = model.id
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
                                
                                if model.id == viewModel.draftModelId {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(model.id == viewModel.draftModelId ? Color.accentColor.opacity(0.1) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    private var addCustomProviderSheet: some View {
        VStack(spacing: 16) {
            Text("添加自定义提供商")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                labeledTextField("名称", text: $viewModel.customName)
                labeledTextField("Base URL", text: $viewModel.customBaseURL)
                labeledTextField("API Key（可选）", text: $viewModel.customApiKey)
            }
            
            HStack {
                Button("取消") { viewModel.showCustomSheet = false }
                Spacer()
                Button("添加") {
                    let name = viewModel.customName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let url = viewModel.customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty, !url.isEmpty else { return }
                    agent.registry.addCustomProvider(name: name, baseURL: url, apiKey: viewModel.customApiKey)
                    viewModel.customName = ""
                    viewModel.customBaseURL = ""
                    viewModel.customApiKey = ""
                    viewModel.showCustomSheet = false
                }
                .disabled(!viewModel.customName.isNotBlank || !viewModel.customBaseURL.isNotBlank)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
    
    private func labeledTextField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
    
    private func loadFromConfig() {
        viewModel.selectedProviderId = agent.config.providerId
        viewModel.draftBaseURL = agent.config.baseURL
        viewModel.draftApiKey = agent.config.apiKey
        viewModel.draftModelId = agent.config.modelId
    }
    
    private func selectProvider(_ provider: Provider) {
        viewModel.selectedProviderId = provider.id
        viewModel.draftBaseURL = provider.baseURL
        viewModel.draftApiKey = provider.apiKey
        
        let firstLive = provider.models.first(where: \.isLive)
        let firstModel = firstLive ?? provider.models.first
        viewModel.draftModelId = firstModel?.id ?? ""
        
        discoverModels()
    }
    
    private func discoverModels() {
        viewModel.isDiscovering = true
        agent.registry.setApiKey(viewModel.draftApiKey, for: viewModel.selectedProviderId)
        
        if let idx = agent.registry.providers.firstIndex(where: { $0.id == viewModel.selectedProviderId }) {
            agent.registry.providers[idx].baseURL = viewModel.draftBaseURL
        }
        
        Task {
            await agent.registry.discoverLiveModels(for: viewModel.selectedProviderId)
            viewModel.isDiscovering = false
            
            if viewModel.draftModelId.isEmpty,
               let provider = agent.registry.provider(for: viewModel.selectedProviderId),
               let first = provider.models.first(where: \.isLive) {
                viewModel.draftModelId = first.id
            }
        }
    }
}

#Preview {
    ModelSettingsView(agent: AgentManager.shared, viewModel: ModelSettingsViewModel())
        .frame(width: 600)
}
