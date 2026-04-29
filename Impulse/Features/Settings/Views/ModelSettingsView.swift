import SwiftUI

struct ModelSettingsView: View {
    @ObservedObject var agent: AgentManager
    @ObservedObject var viewModel: ModelSettingsViewModel
    @State private var didRequestNetworkProviders = false
    @State private var providerOptionsProviderId: String?

    private let fieldWidth: CGFloat = 560
    private let modelListWidth: CGFloat = 560
    private let providerListWidth: CGFloat = 560
    private let providerPageSize = 5
    
    private var currentProvider: Provider? {
        agent.registry.provider(for: viewModel.selectedProviderId)
    }

    private var ollamaProvider: Provider? {
        agent.registry.provider(for: "ollama")
    }

    private var customProviders: [Provider] {
        agent.registry.providers.filter(\.isCustom)
    }

    private var catalogProviders: [Provider] {
        agent.registry.providers.filter { provider in
            provider.id != "ollama" && !provider.isCustom
        }
    }

    private var visibleCatalogProviders: [Provider] {
        Array(catalogProviders.prefix(viewModel.visibleProviderCount))
    }
    
    var body: some View {
        SettingsCard(title: "settings.model.connection") {
            VStack(alignment: .leading, spacing: 14) {
                connectionStatusRow
                
                Divider()
                
                providerSection
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
            Text("settings.model.provider")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            ScrollView {
                LazyVStack(spacing: 0) {
                    if let ollamaProvider {
                        providerRow(ollamaProvider, systemImage: "desktopcomputer")
                    }

                    providerDivider

                    customProviderRows

                    providerDivider

                    ForEach(visibleCatalogProviders) { provider in
                        providerRow(provider, systemImage: "cloud")
                    }

                    if viewModel.visibleProviderCount < catalogProviders.count {
                        loadMoreProviderRow
                            .onAppear {
                                loadMoreProvidersIfNeeded()
                            }
                    }
                }
                .padding(6)
            }
            .frame(width: providerListWidth, height: 238, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.62))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                    )
            )
        }
    }

    @ViewBuilder
    private var customProviderRows: some View {
        if customProviders.isEmpty {
            Button {
                viewModel.showCustomSheet = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("settings.model.add_custom_provider")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                        Text("settings.model.custom_provider")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            ForEach(customProviders) { provider in
                providerRow(provider, systemImage: "slider.horizontal.3")
            }

            Button {
                viewModel.showCustomSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text("settings.model.add_custom_provider")
                        .font(.system(size: 12.5, weight: .medium))
                    Spacer()
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var providerDivider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.08))
            .frame(height: 1)
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
    }

    private var loadMoreProviderRow: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("settings.model.loading_more_providers")
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }

    private func loadMoreProvidersIfNeeded() {
        viewModel.loadMoreProviders(totalCount: catalogProviders.count, pageSize: providerPageSize)

        guard !didRequestNetworkProviders,
              viewModel.visibleProviderCount >= catalogProviders.count,
              !agent.registry.isLoading
        else { return }

        didRequestNetworkProviders = true
        Task {
            await agent.registry.refresh()
            viewModel.loadMoreProviders(totalCount: catalogProviders.count, pageSize: providerPageSize)
        }
    }

    private func providerRow(_ provider: Provider, systemImage: String) -> some View {
        let selected = provider.id == viewModel.selectedProviderId

        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(selected ? Color.accentColor.opacity(0.16) : Color.black.opacity(0.05))
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(selected ? .accentColor : .secondary)
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(provider.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if provider.isCustom {
                        Text("settings.model.custom_provider")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.black.opacity(0.06))
                            )
                    }
                }

                Text(provider.baseURL)
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if provider.isCustom {
                Button(role: .destructive) {
                    deleteCustomProvider(provider)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
            }

            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.accentColor)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.85))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .onTapGesture {
            selectProvider(provider)
            providerOptionsProviderId = provider.id
        }
        .popover(
            isPresented: Binding(
                get: { providerOptionsProviderId == provider.id },
                set: { isPresented in
                    if !isPresented, providerOptionsProviderId == provider.id {
                        providerOptionsProviderId = nil
                    }
                }
            ),
            arrowEdge: .trailing
        ) {
            providerOptionsPanel(providerId: provider.id)
        }
    }

    @ViewBuilder
    private func providerOptionsPanel(providerId: String) -> some View {
        if let provider = agent.registry.provider(for: providerId) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)

                        Text(provider.baseURL)
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    Button {
                        providerOptionsProviderId = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)
                }

                Divider()

                connectionFieldsSection(provider: provider)

                Divider()

                modelPickerSection(provider: provider)
            }
            .padding(16)
            .frame(width: 610, alignment: .leading)
        }
    }
    
    private func connectionFieldsSection(provider: Provider) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("settings.model.connection_parameters")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            
            VStack(spacing: 10) {
                labeledTextField("Base URL", text: $viewModel.draftBaseURL)
                
                HStack(spacing: 10) {
                    Group {
                        if viewModel.showAPIKey {
                            TextField(L10n.tr("settings.model.api_key_placeholder"), text: $viewModel.draftApiKey)
                        } else {
                            SecureField(L10n.tr("settings.model.api_key_placeholder"), text: $viewModel.draftApiKey)
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
                .frame(maxWidth: fieldWidth, alignment: .leading)
                
                if !provider.envKeys.isEmpty {
                    Text(String(format: L10n.tr("settings.model.env_vars"), provider.envKeys.joined(separator: ", ")))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                HStack {
                    Button("settings.model.discover_models") {
                        discoverModels()
                    }
                    .disabled(viewModel.isDiscovering)
                    Spacer()
                }
                .frame(maxWidth: fieldWidth, alignment: .leading)
            }
        }
    }
    
    private func modelPickerSection(provider: Provider) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("settings.model.select_model")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            
            Group {
                let models = provider.models
                if models.isEmpty {
                    Text("settings.model.no_models_hint")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    labeledTextField("settings.model.manual_model_name", text: $viewModel.draftModelId)
                } else {
                    VStack(spacing: 0) {
                        let liveModels = models.filter(\.isLive)
                        let catalogModels = models.filter { !$0.isLive }
                        
                        if !liveModels.isEmpty {
                            modelSection(title: L10n.tr("settings.model.live_models_count", liveModels.count), models: liveModels, live: true)
                        }
                        
                        if !catalogModels.isEmpty {
                            modelSection(title: L10n.tr("settings.model.catalog_models"), models: catalogModels, live: false)
                        }
                    }
                    .frame(maxWidth: modelListWidth, alignment: .leading)
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
                                    Text("settings.model.reasoning")
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
            Text("settings.model.add_custom_provider")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                labeledTextField("settings.model.name", text: $viewModel.customName)
                labeledTextField("Base URL", text: $viewModel.customBaseURL)
                labeledTextField("settings.model.api_key_optional", text: $viewModel.customApiKey)
            }
            
            HStack {
                Button("common.cancel") { viewModel.showCustomSheet = false }
                Spacer()
                Button("common.add") {
                    let name = viewModel.customName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let url = viewModel.customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty, !url.isEmpty else { return }
                    agent.registry.addCustomProvider(name: name, baseURL: url, apiKey: viewModel.customApiKey)
                    if let provider = agent.registry.providers.last(where: { $0.isCustom && $0.name == name && $0.baseURL == url }) {
                        selectProvider(provider)
                    }
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
    
    private func labeledTextField(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: fieldWidth, alignment: .leading)
        }
        .frame(maxWidth: fieldWidth, alignment: .leading)
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

    private func deleteCustomProvider(_ provider: Provider) {
        agent.registry.removeCustomProvider(provider.id)
        if viewModel.selectedProviderId == provider.id {
            if let fallback = ollamaProvider ?? agent.registry.providers.first {
                selectProvider(fallback)
            } else {
                viewModel.selectedProviderId = ""
                viewModel.draftBaseURL = ""
                viewModel.draftApiKey = ""
                viewModel.draftModelId = ""
            }
        }
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
