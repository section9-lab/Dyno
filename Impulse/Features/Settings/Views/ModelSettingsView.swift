import SwiftUI

struct ModelSettingsView: View {
    @ObservedObject var agent: AgentManager
    @ObservedObject var viewModel: ModelSettingsViewModel
    @ObservedObject private var registry = ModelRegistry.shared
    @State private var didRequestNetworkProviders = false
    @State private var providerOptionsProviderId: String?

    @State private var isTesting = false
    @State private var testResult: ModelTestResult? = nil
    @State private var favoriteRowStates: [String: FavoriteRowState] = [:]
    @State private var showProviderSheet = false
    @State private var showEditFavoriteSheet = false

    private enum ModelTestResult {
        case success(latency: String)
        case failure(message: String)
    }

    private enum FavoriteRowState {
        case testing
        case success(latency: String)
        case failure(message: String)

        var isTesting: Bool {
            if case .testing = self { return true }
            return false
        }
    }

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

                if !agent.registry.favorites.isEmpty {
                    Divider()
                    favoritesSection
                }

                Divider()

                addProviderButton
            }
        }
        .sheet(isPresented: $viewModel.showCustomSheet) {
            addCustomProviderSheet
        }
        .sheet(isPresented: $showProviderSheet) {
            providerSheet
        }
        .sheet(isPresented: $showEditFavoriteSheet) {
            editFavoriteSheet
        }
    }

    private var addProviderButton: some View {
        Button {
            showProviderSheet = true
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.14))
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
                .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Model Provider")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    Text(L10n.tr("settings.model.provider"))
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.85))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(width: providerListWidth, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.62))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var providerSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L10n.tr("settings.model.provider"))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    showProviderSheet = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
            }

            providerSection

            HStack {
                Spacer()
                Button(L10n.tr("common.close")) { showProviderSheet = false }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: providerListWidth + 60)
    }

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("settings.model.connected_models"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            VStack(spacing: 4) {
                ForEach(Array(agent.registry.favoriteModels().enumerated()), id: \.offset) { _, entry in
                    favoriteRow(provider: entry.provider, model: entry.model)
                }
            }
            .padding(6)
            .frame(width: providerListWidth, alignment: .leading)
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

    private func favoriteRow(provider: Provider, model: ModelInfo) -> some View {
        let isActive = provider.id == agent.config.providerId && model.id == agent.config.modelId
        let testKey = "\(provider.id)::\(model.id)"
        let rowState = favoriteRowStates[testKey]

        return HStack(spacing: 10) {
            ZStack {
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.accentColor)
                }
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(provider.name)
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let state = rowState {
                switch state {
                case .testing:
                    ProgressView().controlSize(.small)
                case .success(let latency):
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text(latency).font(.system(size: 11)).foregroundColor(.green)
                case .failure(let msg):
                    Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                    Text(msg).font(.system(size: 11)).foregroundColor(.red).lineLimit(1)
                }
            }

            Button {
                testFavorite(provider: provider, model: model)
            } label: {
                Image(systemName: "bolt.horizontal")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .foregroundColor(.secondary)
            .disabled(rowState?.isTesting == true)
            .help("common.test")

            Button {
                editFavorite(provider: provider, model: model)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .foregroundColor(.secondary)
            .help("common.edit")

            Button(role: .destructive) {
                agent.registry.removeFavorite(providerId: provider.id, modelId: model.id)
                favoriteRowStates.removeValue(forKey: testKey)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .foregroundColor(.secondary)
            .help("common.delete")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
        )
    }

    /// Open a dedicated edit sheet for a connected (favorited) model. We
    /// reuse `providerOptionsPanel` content directly — the user just wants
    /// to tweak base URL / API key / pick a different model for THIS row,
    /// not navigate the full provider catalog. Routing here through the
    /// provider grid sheet would put the "Add Custom Provider" tile in
    /// the way, which is exactly the surface they asked us to keep
    /// separate from row-level edits.
    private func editFavorite(provider: Provider, model: ModelInfo) {
        selectProvider(provider)
        viewModel.draftModelId = model.id
        providerOptionsProviderId = provider.id
        showEditFavoriteSheet = true
    }

    @ViewBuilder
    private var editFavoriteSheet: some View {
        if let providerId = providerOptionsProviderId {
            providerOptionsPanel(providerId: providerId)
        }
    }

    private func testFavorite(provider: Provider, model: ModelInfo) {
        let key = "\(provider.id)::\(model.id)"
        favoriteRowStates[key] = .testing
        let baseURL = provider.baseURL
        let apiKey = provider.apiKey

        Task {
            let start = Date()
            let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
            guard let url = URL(string: "\(base)/chat/completions") else {
                favoriteRowStates[key] = .failure(message: "URL 无效")
                return
            }
            var request = URLRequest(url: url, timeoutInterval: 15)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            let body: [String: Any] = [
                "model": model.id,
                "messages": [["role": "user", "content": "hi"]],
                "max_tokens": 1,
                "stream": false
            ]
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (_, response) = try await URLSession.shared.data(for: request)
                let elapsed = String(format: "%.0fms", Date().timeIntervalSince(start) * 1000)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    favoriteRowStates[key] = .success(latency: elapsed)
                } else if let http = response as? HTTPURLResponse {
                    favoriteRowStates[key] = .failure(message: "HTTP \(http.statusCode)")
                } else {
                    favoriteRowStates[key] = .failure(message: "无响应")
                }
            } catch {
                favoriteRowStates[key] = .failure(message: error.localizedDescription)
            }
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
            Text(L10n.tr("settings.model.provider"))
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
            .frame(width: providerListWidth, height: 460, alignment: .leading)
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
                openCustomProviderEditorForAdd()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.tr("settings.model.add_custom_provider"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                        Text(L10n.tr("settings.model.custom_provider"))
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
                openCustomProviderEditorForAdd()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text(L10n.tr("settings.model.add_custom_provider"))
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
            Text(L10n.tr("settings.model.loading_more_providers"))
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
                        Text(L10n.tr("settings.model.custom_provider"))
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
            if provider.isCustom {
                // Custom providers route through the unified editor sheet so
                // add and edit feel like the same surface, with the same
                // fields (name, base URL, key, protocol, optional model).
                openCustomProviderEditor(for: provider)
            } else {
                // Built-in providers keep the inline popover — name and
                // protocol are fixed, the user is just picking a model and
                // entering a key.
                selectProvider(provider, autoPickModel: false)
                providerOptionsProviderId = provider.id
            }
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
                        dismissProviderOptions()
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
            .frame(width: 500, alignment: .leading)
        }
    }
    
    private func connectionFieldsSection(provider: Provider) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("settings.model.connection_parameters"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                labeledTextField("settings.model.base_url", text: $viewModel.draftBaseURL)

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.tr("settings.model.api_key_optional"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
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
                }
                .frame(maxWidth: fieldWidth, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.tr("settings.model.api_protocol"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    perModelApiKindPicker(provider: provider)
                }
                .frame(maxWidth: fieldWidth, alignment: .leading)
            }
        }
    }

    /// Per-model wire protocol picker. "Auto" inherits the provider's
    /// default (or a sniff of the model id if it looks like Claude /
    /// Gemini). The user can pin a specific protocol when the heuristic
    /// is wrong — the typical case is a relay (Nvidia, OpenRouter,
    /// custom gateway) that fronts both Claude (Anthropic shape) and
    /// open-source models (OpenAI shape) on the same base URL.
    @ViewBuilder
    private func perModelApiKindPicker(provider: Provider) -> some View {
        let modelId = viewModel.draftModelId
        let stored = provider.models.first(where: { $0.id == modelId })
        let resolved = provider.effectiveApiKind(forModelId: modelId)
        let autoLabel = L10n.tr("settings.model.api_protocol_auto", resolved.displayName)

        Picker(
            L10n.tr("settings.model.api_protocol"),
            selection: Binding<ApiKind?>(
                get: { stored?.apiKind },
                set: { newValue in
                    guard !modelId.isEmpty else { return }
                    agent.registry.setModelApiKind(
                        providerId: provider.id,
                        modelId: modelId,
                        apiKind: newValue
                    )
                }
            )
        ) {
            Text(autoLabel).tag(ApiKind?.none)
            ForEach(ApiKind.allCases, id: \.self) { kind in
                Text(kind.displayName).tag(ApiKind?.some(kind))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .disabled(modelId.isEmpty)
    }
    
    private func modelPickerSection(provider: Provider) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("settings.model.select_model"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            Group {
                // 128K context-window floor only applies to the curated
                // catalog providers — Ollama and user-added custom providers
                // bypass it because their models often have no published
                // context metadata, and the user is the source of truth for
                // what they want to use locally.
                let bypassContextFilter = provider.isCustom || provider.id == "ollama"
                let models = provider.models
                    .filter(\.isChatCompatible)
                    .filter { bypassContextFilter || ($0.contextWindow ?? 0) > 128_000 }
                let liveModels = models.filter(\.isLive)

                if liveModels.isEmpty {
                    labeledTextField("settings.model.manual_model_name", text: $viewModel.draftModelId)
                } else {
                    modelSection(title: L10n.tr("settings.model.live_models_count", liveModels.count), models: liveModels, live: true)
                        .frame(maxWidth: modelListWidth, alignment: .leading)
                }
            }

            // Test model row
            HStack(spacing: 10) {
                Button(L10n.tr("settings.model.test_model")) {
                    testModel()
                }
                .disabled(isTesting || viewModel.draftModelId.isEmpty || viewModel.draftBaseURL.isEmpty)

                if isTesting {
                    ProgressView().controlSize(.small)
                    Text(L10n.tr("settings.model.testing")).font(.system(size: 12)).foregroundColor(.secondary)
                } else if let result = testResult {
                    switch result {
                    case .success(let latency):
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        Text(L10n.tr("settings.model.test.success", latency)).font(.system(size: 12)).foregroundColor(.green)
                    case .failure(let msg):
                        Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                        Text(msg).font(.system(size: 12)).foregroundColor(.red).lineLimit(1)
                    }
                }

                Spacer()

                Button(L10n.tr("common.cancel")) {
                    dismissProviderOptions()
                }
                .buttonStyle(.bordered)

                Button(L10n.tr("common.save")) {
                    saveSelectedModel()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.draftModelId.isEmpty || viewModel.draftBaseURL.isEmpty)
            }
            .padding(.top, 4)
        }
    }
    
    private func modelSection(title: String, models: [ModelInfo], live: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
                .padding(.top, 6)

            // Use a plain VStack when the list is short so the popover sizes
            // to content instead of holding empty space (a ScrollView always
            // claims its parent's full height, even with one row).
            //
            // For longer lists, the ScrollView needs a *definite* height —
            // not just `maxHeight` — otherwise SwiftUI uses the LazyVStack's
            // first-pass ideal height (~one row) and the popover ends up
            // collapsed to a single row even though `liveModels.count` is
            // already 26. `.frame(height:)` here forces the ScrollView to
            // claim the full slot and lets the LazyVStack scroll inside.
            if models.count > 8 {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(models) { model in
                            modelRow(model, live: live)
                        }
                    }
                }
                .frame(height: 360)
            } else {
                VStack(spacing: 2) {
                    ForEach(models) { model in
                        modelRow(model, live: live)
                    }
                }
            }
        }
    }

    private func modelRow(_ model: ModelInfo, live: Bool) -> some View {
        let favorited = agent.registry.isFavorite(providerId: viewModel.selectedProviderId, modelId: model.id)
        return Button {
            toggleFavorite(model: model)
        } label: {
            HStack(spacing: 8) {
                Button {
                    agent.registry.toggleFavorite(providerId: viewModel.selectedProviderId, modelId: model.id)
                } label: {
                    Image(systemName: favorited ? "checkmark.square.fill" : "square")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(favorited ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)

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

                ModelCapabilityBadges(model: model)

                if let ctx = model.contextWindow {
                    Text("\(ctx / 1000)K")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
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
    
    private var addCustomProviderSheet: some View {
        // Single editor used for both adding a new custom provider and
        // editing an existing one — `viewModel.editingCustomProviderId`
        // distinguishes the two modes. Keeping these flows on one surface
        // avoids the older split where "Add" had a stripped-down form and
        // "Edit" had a richer popover, which felt like two unrelated
        // tools for the same job.
        let isEditing = viewModel.editingCustomProviderId != nil

        return VStack(spacing: 16) {
            HStack {
                Text(isEditing
                     ? L10n.tr("settings.model.edit_custom_provider")
                     : L10n.tr("settings.model.add_custom_provider"))
                    .font(.headline)
                Spacer()
                Button {
                    closeCustomProviderEditor()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                labeledTextField("settings.model.name", text: $viewModel.customName)
                labeledTextField("settings.model.base_url", text: $viewModel.customBaseURL)

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.tr("settings.model.api_key_optional"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    HStack(spacing: 10) {
                        Group {
                            if viewModel.showAPIKey {
                                TextField(L10n.tr("settings.model.api_key_placeholder"), text: $viewModel.customApiKey)
                            } else {
                                SecureField(L10n.tr("settings.model.api_key_placeholder"), text: $viewModel.customApiKey)
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
                }
                .frame(maxWidth: fieldWidth, alignment: .leading)

                labeledTextField("settings.model.model_optional", text: $viewModel.customModelId)
                customApiKindPicker
            }

            HStack {
                if isEditing {
                    Button(role: .destructive) {
                        deleteEditingCustomProvider()
                    } label: {
                        Label(L10n.tr("common.delete"), systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
                Button(L10n.tr("common.cancel")) {
                    closeCustomProviderEditor()
                }
                Button(isEditing ? L10n.tr("common.save") : L10n.tr("common.add")) {
                    commitCustomProviderEditor()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.customName.isNotBlank || !viewModel.customBaseURL.isNotBlank)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    /// Open the unified editor in "add" mode (blank draft). Routed through
    /// here rather than letting each call site flip flags so we can't drift
    /// into a half-loaded state.
    private func openCustomProviderEditorForAdd() {
        viewModel.resetCustomProviderDraft()
        viewModel.showCustomSheet = true
    }

    /// Open the unified editor in "edit" mode, preloaded with the given
    /// custom provider's persisted values.
    private func openCustomProviderEditor(for provider: Provider) {
        viewModel.editingCustomProviderId = provider.id
        viewModel.customName = provider.name
        viewModel.customBaseURL = provider.baseURL
        viewModel.customApiKey = provider.apiKey
        // Surface the most-recently-used live model so users can spot it
        // and tweak; if there are no live models, leave blank.
        viewModel.customModelId = provider.models
            .first(where: { $0.isLive && $0.isChatCompatible })?.id
            ?? ""
        viewModel.customApiKindOverride = provider.apiKind
        viewModel.showCustomSheet = true
    }

    private func closeCustomProviderEditor() {
        viewModel.showCustomSheet = false
        viewModel.resetCustomProviderDraft()
    }

    private func deleteEditingCustomProvider() {
        guard let providerId = viewModel.editingCustomProviderId,
              let provider = agent.registry.provider(for: providerId) else { return }
        deleteCustomProvider(provider)
        closeCustomProviderEditor()
    }

    private func commitCustomProviderEditor() {
        let name = viewModel.customName.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = viewModel.customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !url.isEmpty else { return }

        if let providerId = viewModel.editingCustomProviderId {
            agent.registry.updateCustomProvider(
                id: providerId,
                name: name,
                baseURL: url,
                apiKey: viewModel.customApiKey,
                modelId: viewModel.customModelId,
                apiKind: viewModel.customApiKindOverride
            )
            if let provider = agent.registry.provider(for: providerId) {
                selectProvider(provider)
            }
        } else {
            agent.registry.addCustomProvider(
                name: name,
                baseURL: url,
                apiKey: viewModel.customApiKey,
                modelId: viewModel.customModelId,
                apiKind: viewModel.customApiKindOverride
            )
            if let provider = agent.registry.providers.last(where: { $0.isCustom && $0.name == name && $0.baseURL == url }) {
                selectProvider(provider)
            }
        }

        closeCustomProviderEditor()
    }

    /// Lets the user pin the wire protocol when sniff would guess wrong.
    /// "Auto" runs `ApiKind.sniff` on the typed URL — correct for the
    /// official OpenAI / Anthropic / Gemini hostnames but defaults to
    /// OpenAI Chat Completions for everything else, which is the trap
    /// behind 403s on Anthropic-compatible proxies.
    private var customApiKindPicker: some View {
        let sniffed = ApiKind.sniff(baseURL: viewModel.customBaseURL)
        return VStack(alignment: .leading, spacing: 6) {
            Text(L10n.tr("settings.model.api_protocol"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            Picker(L10n.tr("settings.model.api_protocol"), selection: $viewModel.customApiKindOverride) {
                Text(L10n.tr("settings.model.api_protocol_auto", sniffed.displayName))
                    .tag(ApiKind?.none)
                ForEach(ApiKind.allCases, id: \.self) { kind in
                    Text(kind.displayName).tag(ApiKind?.some(kind))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
    }
    
    private func labeledTextField(_ titleKey: String, text: Binding<String>) -> some View {
        let title = L10n.tr(titleKey)
        return VStack(alignment: .leading, spacing: 6) {
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
    
    /// Pre-loads `draftBaseURL` / `draftApiKey` from the persisted provider
    /// so the user doesn't have to re-type them. `autoPickModel` controls
    /// whether to seed `draftModelId` with the provider's first chat model
    /// — true for the favorite-edit and post-add flows, false when the
    /// user clicks a template in the provider grid (we don't want the
    /// "add a new model from this template" view to look pre-selected).
    private func selectProvider(_ provider: Provider, autoPickModel: Bool = true) {
        viewModel.selectedProviderId = provider.id
        viewModel.draftBaseURL = provider.baseURL
        viewModel.draftApiKey = provider.apiKey

        if autoPickModel {
            let firstLive = provider.models.first { $0.isLive && $0.isChatCompatible }
            let firstModel = firstLive ?? provider.models.first(where: \.isChatCompatible)
            viewModel.draftModelId = firstModel?.id ?? ""
        } else {
            viewModel.draftModelId = ""
        }

        discoverModels(autoPickModel: autoPickModel)
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
    
    private func toggleFavorite(model: ModelInfo) {
        let providerId = viewModel.selectedProviderId
        guard !providerId.isEmpty else { return }
        if agent.registry.isFavorite(providerId: providerId, modelId: model.id) {
            agent.registry.removeFavorite(providerId: providerId, modelId: model.id)
        } else {
            agent.registry.addFavorite(providerId: providerId, modelId: model.id)
            viewModel.draftModelId = model.id
        }
    }

    private func saveSelectedModel() {
        var newConfig = agent.config
        newConfig.providerId = viewModel.selectedProviderId
        newConfig.baseURL = viewModel.draftBaseURL
        newConfig.apiKey = viewModel.draftApiKey
        newConfig.modelId = viewModel.draftModelId
        // Resolve the wire protocol per-model so `claude-*` entries hosted
        // by an OpenAI-shaped relay (or vice versa) hit the right route.
        if let provider = agent.registry.provider(for: viewModel.selectedProviderId) {
            newConfig.apiKind = provider.effectiveApiKind(forModelId: viewModel.draftModelId)
        }
        Task {
            await agent.applyConfig(newConfig)
            dismissProviderOptions()
        }
    }

    private func dismissProviderOptions() {
        providerOptionsProviderId = nil
        showEditFavoriteSheet = false
    }

    private func testModel() {
        guard !viewModel.draftModelId.isEmpty, !viewModel.draftBaseURL.isEmpty else { return }
        isTesting = true
        testResult = nil

        Task {
            let start = Date()
            do {
                let base = viewModel.draftBaseURL.hasSuffix("/") ? String(viewModel.draftBaseURL.dropLast()) : viewModel.draftBaseURL
                guard let url = URL(string: "\(base)/chat/completions") else {
                    testResult = .failure(message: "URL 无效")
                    isTesting = false
                    return
                }
                var request = URLRequest(url: url, timeoutInterval: 15)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                if !viewModel.draftApiKey.isEmpty {
                    request.setValue("Bearer \(viewModel.draftApiKey)", forHTTPHeaderField: "Authorization")
                }
                let body: [String: Any] = [
                    "model": viewModel.draftModelId,
                    "messages": [["role": "user", "content": "hi"]],
                    "max_tokens": 1,
                    "stream": false
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (_, response) = try await URLSession.shared.data(for: request)
                let elapsed = String(format: "%.0fms", Date().timeIntervalSince(start) * 1000)

                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    testResult = .success(latency: elapsed)
                } else if let http = response as? HTTPURLResponse {
                    testResult = .failure(message: "HTTP \(http.statusCode)")
                } else {
                    testResult = .failure(message: "无响应")
                }
            } catch {
                testResult = .failure(message: error.localizedDescription)
            }
            isTesting = false
        }
    }

    /// `autoPickModel` mirrors the flag from `selectProvider`: when the user
    /// is just browsing a built-in provider's list (autoPickModel: false), we
    /// must NOT seed `draftModelId` from the discovered list — otherwise the
    /// outer Save in `SettingsContainerView` would silently switch the active
    /// model to whichever live model came back first, even though the user
    /// never clicked it.
    private func discoverModels(autoPickModel: Bool = true) {
        viewModel.isDiscovering = true
        agent.registry.setApiKey(viewModel.draftApiKey, for: viewModel.selectedProviderId)

        if let idx = agent.registry.providers.firstIndex(where: { $0.id == viewModel.selectedProviderId }) {
            agent.registry.providers[idx].baseURL = viewModel.draftBaseURL
        }

        Task {
            await agent.registry.discoverLiveModels(for: viewModel.selectedProviderId)
            viewModel.isDiscovering = false

            guard autoPickModel else { return }

            if viewModel.draftModelId.isEmpty,
               let provider = agent.registry.provider(for: viewModel.selectedProviderId),
               let first = provider.models.first(where: { $0.isLive && $0.isChatCompatible }) {
                viewModel.draftModelId = first.id
            }
        }
    }
}

#Preview {
    ModelSettingsView(agent: AgentManager.shared, viewModel: ModelSettingsViewModel())
        .frame(width: 600)
}
