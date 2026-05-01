import SwiftUI

struct ModelProviderConfigView: View {
    @ObservedObject var agent: AgentManager
    @StateObject private var sandbox = SandboxAccessManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProviderId: String = ""
    @State private var draftApiKey: String = ""
    @State private var draftBaseURL: String = ""
    @State private var draftModelId: String = ""
    @State private var showAPIKey = false
    @State private var isDiscovering = false

    @State private var isTesting = false
    @State private var testResult: ModelTestResult? = nil

    private enum ModelTestResult {
        case success(latency: String)
        case failure(message: String)
    }

    @State private var showCustomSheet = false
    @State private var customName = ""
    @State private var customBaseURL = ""
    @State private var customApiKey = ""
    @State private var selectedTextPreview: SandboxTextPreview?
    @State private var expandedFolders: Set<String> = []
    @State private var agentEntries: [SandboxTreeRowEntry] = []

    private var currentProvider: Provider? {
        agent.registry.provider(for: selectedProviderId)
    }

    private var storageDirectoryURL: URL {
        agent.storageDirectoryURL
    }

    private var canSave: Bool {
        draftBaseURL.isNotBlank && draftModelId.isNotBlank
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    modelConnectionCard
                    agentStateCard
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
                refreshAgentEntries()
            }
            .sheet(isPresented: $showCustomSheet) {
                addCustomProviderSheet
            }
        }
        .frame(minWidth: 640, minHeight: 560)
        .sheet(item: $selectedTextPreview) { preview in
            NavigationStack {
                ScrollView {
                    Text(preview.content)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(16)
                }
                .navigationTitle(preview.title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") {
                            selectedTextPreview = nil
                        }
                    }
                }
            }
            .frame(minWidth: 640, minHeight: 460)
        }
    }

    // MARK: - Model Connection

    private var modelConnectionCard: some View {
        SettingsCard(title: "模型连接") {
            VStack(alignment: .leading, spacing: 14) {
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

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("模型提供商")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)

                    providerGridContent
                }

                if !selectedProviderId.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("连接参数")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)

                        connectionFields
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("选择模型")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)

                        modelPickerContent
                    }
                }
            }
        }
    }

    private var providerGridContent: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
            ForEach(agent.registry.providers) { provider in
                providerCard(provider)
            }
            addCustomCard
        }
    }

    private var connectionFields: some View {
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

    // MARK: - Model Picker

    private var modelPickerContent: some View {
        Group {
            let models = currentProvider?.models ?? []
            if models.isEmpty {
                labeledTextField("模型名称", text: $draftModelId)
            } else {
                VStack(spacing: 0) {
                    let liveModels = models.filter(\.isLive)

                    if !liveModels.isEmpty {
                        modelSection(title: "可用模型（\(liveModels.count)）", models: liveModels, live: true)
                    } else {
                        labeledTextField("模型名称", text: $draftModelId)
                    }
                }
                .frame(maxHeight: 240)
            }

            // Test button row
            HStack(spacing: 10) {
                if isTesting {
                    ProgressView().controlSize(.small)
                    Text("测试中…").font(.system(size: 12)).foregroundColor(.secondary)
                } else if let result = testResult {
                    switch result {
                    case .success(let latency):
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        Text("可用 (\(latency))").font(.system(size: 12)).foregroundColor(.green)
                    case .failure(let msg):
                        Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                        Text(msg).font(.system(size: 12)).foregroundColor(.red).lineLimit(1)
                    }
                }
                Spacer()
                Button("测试模型") {
                    testModel()
                }
                .disabled(isTesting || draftModelId.isEmpty || draftBaseURL.isEmpty)
            }
            .padding(.top, 6)
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

    private var visibleAgentEntries: [SandboxTreeRowEntry] {
        agentEntries
    }

    private var agentStateCard: some View {
        SettingsCard(title: "Impulse 数据目录") {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Storage Root")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(storageDirectoryURL.path)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Active Project")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text(agent.activeProjectPath ?? "未选择")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(agent.activeProjectPath == nil ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleAgentEntries) { entry in
                            agentTreeRow(entry)
                        }
                    }
                }
                .frame(minHeight: 180, maxHeight: 400)
                .padding(10)
                .background(Color.white.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text("Impulse 的会话、skills 和后续 memory 都放在这里，不再跟项目目录绑定。")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("当前执行工作区由左侧 Projects 中选中的项目决定。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func agentTreeRow(_ entry: SandboxTreeRowEntry) -> some View {
        let row = HStack(spacing: 8) {
            if entry.isDirectory && entry.exists {
                Image(systemName: entry.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 10)
            } else {
                Spacer().frame(width: 10)
            }

            Image(systemName: entry.icon)
                .font(.system(size: 12))
                .foregroundColor(entry.iconColor)
                .frame(width: 14, height: 14)

            Text(entry.name)
                .font(.system(size: 12, weight: entry.isDirectory ? .medium : .regular))
                .foregroundColor(entry.nameColor)
                .lineLimit(1)

            Spacer()

            if entry.isTextFile {
                Text("查看")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.accentColor)
            } else if entry.isMissingDirectory {
                Text("未创建")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.leading, CGFloat(entry.depth) * 16)
        .padding(.vertical, 4)
        .contentShape(Rectangle())

        if entry.isDirectory && entry.exists {
            return AnyView(
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        toggleFolder(entry.url)
                    }
                } label: {
                    row
                }
                .buttonStyle(.plain)
            )
        }

        if entry.isTextFile {
            return AnyView(
                Button {
                    openTextPreview(name: entry.name, url: entry.url)
                } label: {
                    row
                }
                .buttonStyle(.plain)
            )
        }

        return AnyView(row)
    }

    private func appendAgentRows(
        for url: URL,
        name: String,
        depth: Int,
        into result: inout [SandboxTreeRowEntry],
        isRoot: Bool = false
    ) {
        let exists = FileManager.default.fileExists(atPath: url.path)
        let key = url.standardizedFileURL.path
        let isExpanded = exists && expandedFolders.contains(key)
        let children = isExpanded ? agentChildren(of: url) : []

        result.append(
            SandboxTreeRowEntry(
                name: name,
                url: url,
                depth: depth,
                isDirectory: true,
                isTextFile: false,
                isRoot: isRoot,
                isExpanded: isExpanded,
                isEmptyDirectory: exists && isExpanded && children.isEmpty,
                exists: exists,
                isMissingDirectory: !exists
            )
        )

        guard exists, isExpanded else { return }

        for child in children {
            let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                appendAgentRows(
                    for: child,
                    name: child.lastPathComponent,
                    depth: depth + 1,
                    into: &result
                )
            } else {
                result.append(
                    SandboxTreeRowEntry(
                        name: child.lastPathComponent,
                        url: child,
                        depth: depth + 1,
                        isDirectory: false,
                        isTextFile: isPreviewableTextFile(child),
                        isRoot: false,
                        isExpanded: false,
                        isEmptyDirectory: false,
                        exists: true,
                        isMissingDirectory: false
                    )
                )
            }
        }

        if children.isEmpty {
            result.append(
                SandboxTreeRowEntry(
                    name: "空目录",
                    url: url,
                    depth: depth + 1,
                    isDirectory: false,
                    isTextFile: false,
                    isRoot: false,
                    isExpanded: false,
                    isEmptyDirectory: true,
                    exists: true,
                    isMissingDirectory: false
                )
            )
        }
    }

    private func toggleFolder(_ url: URL) {
        let key = url.standardizedFileURL.path
        if expandedFolders.contains(key) {
            expandedFolders.remove(key)
        } else {
            expandedFolders.insert(key)
        }
        refreshAgentEntries()
    }

    private func refreshAgentEntries() {
        var result: [SandboxTreeRowEntry] = []
        let roots = agentChildren(of: storageDirectoryURL)

        for url in roots {
            appendAgentRows(for: url, name: url.lastPathComponent, depth: 0, into: &result, isRoot: true)
        }

        agentEntries = result
    }

    private func agentChildren(of url: URL) -> [URL] {
        let rootPath = storageDirectoryURL.standardizedFileURL.path
        let targetPath = url.standardizedFileURL.path
        guard targetPath == rootPath || targetPath.hasPrefix(rootPath + "/") else { return [] }

        guard let children = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return children.sorted { a, b in
            let aDir = (try? a.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let bDir = (try? b.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if aDir != bDir { return aDir }
            return a.lastPathComponent.localizedCaseInsensitiveCompare(b.lastPathComponent) == .orderedAscending
        }
    }

    // MARK: - Execution Roots

    private var sandboxCard: some View {
        SettingsCard(title: "执行授权目录") {
            VStack(spacing: 10) {
                if sandbox.entries.isEmpty {
                    Text("未授权额外目录。当前项目会作为默认执行目录，其它路径需要单独授权。")
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

                Text("这些目录只影响 read/write/edit/bash 等执行工具的可触达范围，不影响 Impulse 自身状态目录。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
    }

    private func selectProvider(_ provider: Provider) {
        selectedProviderId = provider.id
        draftBaseURL = provider.baseURL
        draftApiKey = provider.apiKey

        let firstLive = provider.models.first(where: \.isLive)
        let firstModel = firstLive ?? provider.models.first
        draftModelId = firstModel?.id ?? ""

        discoverModels()
    }

    private func discoverModels() {
        isDiscovering = true
        agent.registry.setApiKey(draftApiKey, for: selectedProviderId)

        if let idx = agent.registry.providers.firstIndex(where: { $0.id == selectedProviderId }) {
            agent.registry.providers[idx].baseURL = draftBaseURL
        }

        Task {
            await agent.registry.discoverLiveModels(for: selectedProviderId)
            isDiscovering = false

            if draftModelId.isEmpty,
               let provider = agent.registry.provider(for: selectedProviderId),
               let first = provider.models.first(where: \.isLive) {
                draftModelId = first.id
            }
        }
    }

    private func testModel() {
        guard !draftModelId.isEmpty, !draftBaseURL.isEmpty else { return }
        isTesting = true
        testResult = nil

        Task {
            let start = Date()
            do {
                let base = draftBaseURL.hasSuffix("/") ? String(draftBaseURL.dropLast()) : draftBaseURL
                guard let url = URL(string: "\(base)/chat/completions") else {
                    testResult = .failure(message: "URL 无效")
                    isTesting = false
                    return
                }

                var request = URLRequest(url: url, timeoutInterval: 15)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                if !draftApiKey.isEmpty {
                    request.setValue("Bearer \(draftApiKey)", forHTTPHeaderField: "Authorization")
                }

                let body: [String: Any] = [
                    "model": draftModelId,
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

    private func saveAndConnect() {
        let newConfig = AgentServiceConfig(
            providerId: selectedProviderId,
            baseURL: draftBaseURL,
            apiKey: draftApiKey,
            modelId: draftModelId
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

    private func isPreviewableTextFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let allowed = [
            "txt", "md", "markdown", "json", "jsonl", "yaml", "yml",
            "log", "csv", "tsv", "swift", "py", "js", "ts", "tsx", "jsx",
            "html", "css", "xml", "sh"
        ]
        return allowed.contains(ext)
    }

    private func openTextPreview(name: String, url: URL) {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .unicode)
        else {
            selectedTextPreview = SandboxTextPreview(
                title: name,
                content: "无法读取该文件内容。"
            )
            return
        }

        let previewText = content.count > 20_000 ? String(content.prefix(20_000)) + "\n\n… 已截断" : content
        selectedTextPreview = SandboxTextPreview(title: name, content: previewText)
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

private struct SandboxTreeRowEntry: Identifiable {
    let name: String
    let url: URL
    let depth: Int
    let isDirectory: Bool
    let isTextFile: Bool
    let isRoot: Bool
    let isExpanded: Bool
    let isEmptyDirectory: Bool
    let exists: Bool
    let isMissingDirectory: Bool

    var id: String {
        [url.standardizedFileURL.path, String(depth), isDirectory ? "dir" : "file", isExpanded ? "expanded" : "collapsed", exists ? "exists" : "missing", isEmptyDirectory ? "empty" : "filled"].joined(separator: "|")
    }

    var icon: String {
        if isMissingDirectory { return "folder.badge.questionmark" }
        if isEmptyDirectory { return "questionmark.folder" }
        if isRoot { return "internaldrive" }
        if isDirectory { return isExpanded ? "folder.fill" : "folder" }
        return isTextFile ? "doc.text" : "doc"
    }

    var iconColor: Color {
        if isMissingDirectory { return .secondary }
        if isEmptyDirectory { return .secondary.opacity(0.6) }
        if isRoot { return .accentColor }
        return isTextFile ? .accentColor : .secondary
    }

    var nameColor: Color {
        if isMissingDirectory { return .secondary }
        return isEmptyDirectory ? .secondary.opacity(0.6) : (isTextFile ? .accentColor : .primary)
    }
}

private struct SandboxTextPreview: Identifiable {
    let id = UUID()
    let title: String
    let content: String
}
