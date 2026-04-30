import Foundation
import Combine
import SwiftUI
import SwiftCodingAgent

@MainActor
final class AgentManager: ObservableObject {
    static let shared = AgentManager()

    @Published var isResponding: Bool = false
    @Published var isServiceConnected: Bool = false
    @Published var connectionStatusText: String = L10n.tr("agent.status.checking")
    @Published var config: AgentServiceConfig
    @Published var latestToolExecutions: [AgentToolExecution] = []
    @Published var latestCompactionSummary: String?
    @Published var contextUsage: ContextUsage = ContextUsage(usedTokens: 0, totalTokens: 128_000, reservedTokens: 16_384)

    let registry = ModelRegistry.shared

    static var storageDirectoryURL: URL {
        URL(fileURLWithPath: AgentServiceConfig.defaultStorageDirectoryPath)
    }

    var storageDirectoryURL: URL {
        Self.storageDirectoryURL
    }

    static var appDataDirectoryURL: URL {
        URL(fileURLWithPath: AgentServiceConfig.defaultAppDataDirectoryPath)
    }

    @Published private(set) var activeProjectPath: String?

    var activeProjectDirectoryURL: URL? {
        let path = resolvedActiveProjectPath
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    var executionWorkingDirectoryURL: URL {
        activeProjectDirectoryURL ?? Self.defaultExecutionWorkspaceURL
    }

    private var resolvedActiveProjectPath: String {
        activeProjectPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static var defaultExecutionWorkspaceURL: URL {
        URL(fileURLWithPath: AgentServiceConfig.defaultExecutionWorkspacePath)
    }

    private static let configStorageKey = "agent.service.config.v3"

    private var sdk: AgentSDK
    private let sandboxAccess = SandboxAccessManager.shared
    private let sessionStore: AgentSessionStoring = AgentSessionStore()

    private init() {
        let initialConfig = Self.loadConfig() ?? Self.defaultConfigFromEnvironment()
        self.config = initialConfig
        self.sdk = Self.makeSDK(config: initialConfig, activeProjectPath: nil)

        registry.setApiKey(initialConfig.apiKey, for: initialConfig.providerId)

        refreshRuntimeContext()

        Task {
            await registry.refresh()
            await self.refreshServiceStatus()
        }
    }

    func applyConfig(_ newConfig: AgentServiceConfig) async {
        config = newConfig
        latestToolExecutions = []
        latestCompactionSummary = nil

        registry.setApiKey(newConfig.apiKey, for: newConfig.providerId)

        Self.saveConfig(newConfig)
        refreshRuntimeContext()
        await refreshServiceStatus()
    }

    func refreshRuntimeContext() {
        _ = sandboxAccess.authorizedRoots.count
        latestCompactionSummary = nil
        bootstrapAgentDirectory()
        sdk = Self.makeSDK(config: config, activeProjectPath: activeProjectPath)
        Task { await refreshContextUsage() }
    }

    func setActiveProjectPath(_ path: String?) {
        let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPath = (trimmed?.isEmpty == false) ? trimmed : nil
        guard activeProjectPath != normalizedPath else { return }
        activeProjectPath = normalizedPath
        refreshRuntimeContext()
    }

    private func bootstrapAgentDirectory() {
        migrateLegacyAgentDataIfNeeded()

        let storageDirectoryURL = storageDirectoryURL
        let skillsDir = storageDirectoryURL.agentSkillsDirectory()
        let memoryDir = storageDirectoryURL.agentMemoryDirectory()
        let rawMemoryDir = memoryDir.appendingPathComponent("raw", isDirectory: true)

        for dir in [Self.appDataDirectoryURL, storageDirectoryURL, skillsDir, memoryDir, rawMemoryDir, Self.defaultExecutionWorkspaceURL] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private func migrateLegacyAgentDataIfNeeded() {
        let fileManager = FileManager.default
        let legacyRoot = Self.appDataDirectoryURL.appendingPathComponent(".agent", isDirectory: true)
        let newRoot = storageDirectoryURL

        guard legacyRoot.standardizedFileURL.path != newRoot.standardizedFileURL.path else { return }
        guard fileManager.fileExists(atPath: legacyRoot.path) else { return }
        try? fileManager.createDirectory(at: newRoot, withIntermediateDirectories: true)

        for directoryName in ["skills", "memory"] {
            let legacyURL = legacyRoot.appendingPathComponent(directoryName, isDirectory: true)
            let destinationURL = newRoot.appendingPathComponent(directoryName, isDirectory: true)
            guard fileManager.fileExists(atPath: legacyURL.path) else { continue }

            do {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try mergeDirectoryContents(from: legacyURL, into: destinationURL)
                    try removeDirectoryIfEmpty(legacyURL)
                } else {
                    try fileManager.moveItem(at: legacyURL, to: destinationURL)
                }
            } catch {
                print("Failed to migrate legacy agent directory \(legacyURL.path): \(error)")
            }
        }

        try? removeDirectoryIfEmpty(legacyRoot)
    }

    private func mergeDirectoryContents(from source: URL, into destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let children = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey])

        for child in children {
            let target = destination.appendingPathComponent(child.lastPathComponent, isDirectory: false)
            if fileManager.fileExists(atPath: target.path) {
                let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDirectory {
                    try mergeDirectoryContents(from: child, into: target)
                    try removeDirectoryIfEmpty(child)
                }
            } else {
                try fileManager.moveItem(at: child, to: target)
            }
        }
    }

    private func removeDirectoryIfEmpty(_ url: URL) throws {
        let fileManager = FileManager.default
        let remaining = try fileManager.contentsOfDirectory(atPath: url.path)
        if remaining.isEmpty {
            try fileManager.removeItem(at: url)
        }
    }

    func refreshServiceStatus() async {
        connectionStatusText = L10n.tr("agent.status.checking")

        guard !config.baseURL.isEmpty else {
            isServiceConnected = false
            connectionStatusText = L10n.tr("agent.status.base_url_missing")
            return
        }

        await registry.discoverLiveModels(for: config.providerId)

        let provider = registry.provider(for: config.providerId)
        let liveModels = provider?.models.filter(\.isLive) ?? []

        if liveModels.isEmpty {
            guard let baseURL = URL(string: config.baseURL) else {
                isServiceConnected = false
                connectionStatusText = L10n.tr("agent.status.base_url_invalid")
                return
            }

            var request = URLRequest(url: baseURL.appendingPathComponent("models"))
            request.httpMethod = "GET"
            request.timeoutInterval = 6
            if !config.apiKey.isEmpty {
                request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
            }

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    isServiceConnected = true
                    connectionStatusText = L10n.tr("agent.status.connected", config.modelId)
                } else {
                    isServiceConnected = false
                    connectionStatusText = L10n.tr("agent.status.service_unavailable")
                }
            } catch {
                isServiceConnected = false
                connectionStatusText = L10n.tr("agent.status.connection_failed", error.localizedDescription)
            }
            return
        }

        isServiceConnected = true
        let found = liveModels.contains { $0.id == config.modelId }
        connectionStatusText = found
            ? L10n.tr("agent.status.connected", config.modelId)
            : L10n.tr("agent.status.connected_missing_model", liveModels.count, config.modelId)
    }

    // MARK: - Project/session persistence

    func loadPersistedProjects() -> [ProjectSnapshot] {
        (try? sessionStore.loadProjects(storageDirectory: Self.appDataDirectoryURL.path)) ?? []
    }

    func persistProjects(_ projects: [ProjectSnapshot]) {
        do {
            try sessionStore.saveProjects(projects, storageDirectory: Self.appDataDirectoryURL.path)
        } catch {
            print("Failed to persist project snapshots: \(error)")
        }
    }

    // MARK: - Agent execution

    func sendChat(prompt: String, contextPrelude: String? = nil) async throws -> String {
        isResponding = true
        latestToolExecutions = []
        latestCompactionSummary = nil
        defer { isResponding = false }

        if !isServiceConnected {
            await refreshServiceStatus()
        }

        let historyCountBefore = await sdk.history().count

        var lastToolSignature = ""

        let progressTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let allMessages = await self.sdk.history()
                let runMessages = Array(allMessages.dropFirst(historyCountBefore))
                let polledExecutions = self.extractToolExecutions(from: runMessages)

                let toolSignature = self.signature(for: polledExecutions)
                if polledExecutions.count >= self.latestToolExecutions.count {
                    if toolSignature != lastToolSignature {
                        self.latestToolExecutions = polledExecutions
                        lastToolSignature = toolSignature
                    }
                }

                try? await Task.sleep(for: .milliseconds(450))
            }
        }
        defer { progressTask.cancel() }

        let effectivePrompt: String
        if let contextPrelude, !contextPrelude.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            effectivePrompt = """
            \(contextPrelude)

            [当前用户新消息]
            \(prompt)
            """
        } else {
            effectivePrompt = prompt
        }

        do {
            let result = try await sdk.run(prompt: effectivePrompt)
            let runMessages = Array(result.messages.dropFirst(historyCountBefore))
            latestToolExecutions = extractToolExecutions(from: runMessages)
            latestCompactionSummary = result.compactionSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
            contextUsage = await sdk.contextUsage()

            let text = result.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                if !latestToolExecutions.isEmpty {
                    return L10n.tr("agent.empty_after_tools", latestToolExecutions.count)
                }
                return L10n.tr("agent.empty_model_response")
            }
            return text
        } catch AgentLoopError.maxStepsReached {
            let allMessages = await sdk.history()
            let runMessages = Array(allMessages.dropFirst(historyCountBefore))
            latestToolExecutions = extractToolExecutions(from: runMessages)
            latestCompactionSummary = await sdk.compactionSummary()?.trimmingCharacters(in: .whitespacesAndNewlines)
            contextUsage = await sdk.contextUsage()

            if let lastAssistant = runMessages.last(where: { $0.role == .assistant }),
               !lastAssistant.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return lastAssistant.content
            }

            return L10n.tr("agent.max_steps_reached", latestToolExecutions.count)
        }
    }

    private func signature(for executions: [AgentToolExecution]) -> String {
        executions.map { "\($0.id)|\($0.status.rawValue)|\($0.summary)" }.joined(separator: "||")
    }

    private func extractToolExecutions(from messages: [AgentMessage]) -> [AgentToolExecution] {
        let trackedTools: Set<String> = ["read", "write", "edit", "bash"]

        struct PendingCall {
            let name: String
            let argsJSON: String?
            let order: Int
        }

        var pendingByCallID: [String: PendingCall] = [:]
        var pendingOrder: [String] = []
        var orderCounter = 0

        for message in messages where message.role == .assistant {
            guard let callID = message.toolCallID,
                  let name = message.toolName,
                  trackedTools.contains(name)
            else { continue }
            pendingByCallID[callID] = PendingCall(name: name, argsJSON: message.toolArgumentsJSON, order: orderCounter)
            pendingOrder.append(callID)
            orderCounter += 1
        }

        var executions: [(order: Int, execution: AgentToolExecution)] = []

        for (index, message) in messages.enumerated() {
            guard message.role == .tool,
                  let name = message.toolName,
                  trackedTools.contains(name)
            else { continue }

            let output = message.content
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let failed = trimmed.hasPrefix("ERROR:")
            let stableID = message.toolCallID ?? "\(name)-\(index)"
            let pending = message.toolCallID.flatMap { pendingByCallID[$0] }
            let argsJSON = pending?.argsJSON
            let summary = buildToolSummary(toolName: name, argumentsJSON: argsJSON)
            let displayOutput = failed ? mapToUserFriendlySandboxMessage(trimmed) + "\n\n" + L10n.tr("agent.raw_error") + ":\n\(trimmed)" : output
            let order = pending?.order ?? (1_000_000 + index)

            executions.append((
                order: order,
                execution: AgentToolExecution(
                    id: stableID,
                    toolName: name,
                    status: failed ? .failed : .success,
                    summary: summary,
                    output: displayOutput
                )
            ))

            if let callID = message.toolCallID {
                pendingByCallID.removeValue(forKey: callID)
            }
        }

        // Any remaining pending calls are still running.
        for callID in pendingOrder {
            guard let pending = pendingByCallID[callID] else { continue }
            let summary = buildToolSummary(toolName: pending.name, argumentsJSON: pending.argsJSON)
            executions.append((
                order: pending.order,
                execution: AgentToolExecution(
                    id: callID,
                    toolName: pending.name,
                    status: .running,
                    summary: summary,
                    output: ""
                )
            ))
        }

        return executions.sorted { $0.order < $1.order }.map(\.execution)
    }

    private func buildToolSummary(toolName: String, argumentsJSON: String?) -> String {
        guard let argumentsJSON,
              let data = argumentsJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return toolName }

        switch toolName {
        case "read", "write", "edit":
            let path = (obj["path"] as? String) ?? ""
            if path.isEmpty { return toolName }
            let filename = URL(fileURLWithPath: path).lastPathComponent
            return "\(path) (\(filename))"
        case "bash":
            let command = (obj["command"] as? String) ?? ""
            return command.isEmpty ? "bash" : command
        default:
            return toolName
        }
    }

    private func mapToUserFriendlySandboxMessage(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("outside authorized roots") {
            return L10n.tr("agent.sandbox_error.outside_roots")
        }
        if lower.contains("operation not permitted") || lower.contains("permission denied") {
            return L10n.tr("agent.sandbox_error.permission_denied")
        }
        if lower.contains("no such file") || lower.contains("cannot read file") {
            return L10n.tr("agent.sandbox_error.file_missing")
        }
        return L10n.tr("agent.sandbox_error.operation_failed", raw)
    }

    func compact(customInstructions: String? = nil) async throws -> String? {
        isResponding = true
        latestToolExecutions = []
        defer { isResponding = false }

        if !isServiceConnected {
            await refreshServiceStatus()
        }

        let summary = try await sdk.compact(customInstructions: customInstructions)
        latestCompactionSummary = summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        contextUsage = await sdk.contextUsage()
        return latestCompactionSummary
    }

    func refreshContextUsage() async {
        contextUsage = await sdk.contextUsage()
    }

    private static func makeSDK(config: AgentServiceConfig, activeProjectPath: String?) -> AgentSDK {
        let baseURL = URL(string: config.baseURL) ?? URL(string: "http://127.0.0.1:11434/v1")!
        let storageDirectoryURL = Self.storageDirectoryURL
        let resolvedProjectPath = activeProjectPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let workingDirectoryURL = resolvedProjectPath.isEmpty
            ? defaultExecutionWorkspaceURL
            : URL(fileURLWithPath: resolvedProjectPath)

        let sandboxRoots = SandboxAccessManager.shared.authorizedRoots
        var allowedRoots = [workingDirectoryURL]
        for root in sandboxRoots where !allowedRoots.contains(where: { $0.standardizedFileURL.path == root.standardizedFileURL.path }) {
            allowedRoots.append(root)
        }

        var skillsDirs: [URL] = []
        if let bundledSkills = Bundle.main.resourceURL?.appendingPathComponent("skills", isDirectory: true) {
            skillsDirs.append(bundledSkills)
        }
        skillsDirs.append(storageDirectoryURL.agentSkillsDirectory())

        let allTools: [any AgentTool] = []
        let fileToolPolicy = ToolExecutionPolicy(
            allowedRoots: allowedRoots,
            bash: .disabled
        )
        let bashToolPolicy = ToolExecutionPolicy(
            allowedRoots: allowedRoots,
            bash: .unrestricted
        )
        let toolExecutionContexts: [String: ToolExecutionContext] = [
            "read": ToolExecutionContext(
                workingDirectory: workingDirectoryURL,
                executionPolicy: fileToolPolicy
            ),
            "write": ToolExecutionContext(
                workingDirectory: workingDirectoryURL,
                executionPolicy: fileToolPolicy
            ),
            "edit": ToolExecutionContext(
                workingDirectory: workingDirectoryURL,
                executionPolicy: fileToolPolicy
            ),
            "bash": ToolExecutionContext(
                workingDirectory: workingDirectoryURL,
                executionPolicy: bashToolPolicy
            )
        ]

        return AgentSDK(
            model: OpenAICompatibleChatModel(
                baseURL: baseURL,
                apiKey: config.apiKey.isEmpty ? nil : config.apiKey,
                modelName: config.modelId,
                timeout: 300
            ),
            skills: [
                BasicSkill(
                    name: "default",
                    systemPrompt: """
You are a coding assistant. You help users write, debug, and understand code.

You have access to these tools:
- read: Read files and directories
- write: Create or overwrite files
- edit: Make precise edits to existing files
- bash: Run shell commands

Work directly in the user's project when one is selected. Read files to understand context before making changes. Use bash to run tests, linters, and other development tools.

When a task matches a skill, use the read tool to load the skill's SKILL.md file for detailed instructions, then follow them carefully.

Think step by step. If you're unsure, read more files or ask the user.
"""
                )
            ],
            tools: allTools,
            workingDirectory: workingDirectoryURL,
            allowedRoots: allowedRoots,
            executionPolicy: ToolExecutionPolicy(
                allowedRoots: allowedRoots,
                bash: .disabled
            ),
            toolExecutionContexts: toolExecutionContexts,
            maxSteps: nil,
            skillsDirectories: skillsDirs,
            approvalHandler: { request in
                await ToolApprovalCenter.shared.request(request)
            }
        )
    }

    private static func defaultConfigFromEnvironment() -> AgentServiceConfig {
        let base = ProcessInfo.processInfo.environment["OPENAI_BASE_URL"] ?? "http://127.0.0.1:11434/v1"
        let model = ProcessInfo.processInfo.environment["OPENAI_MODEL"]
            ?? ProcessInfo.processInfo.environment["OLLAMA_MODEL"]
            ?? ""
        let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""

        let providerId = base.contains("11434") ? "ollama" : "custom"
        return AgentServiceConfig(
            providerId: providerId,
            baseURL: base,
            apiKey: key,
            modelId: model
        )
    }

    private static func loadConfig() -> AgentServiceConfig? {
        if let data = UserDefaults.standard.data(forKey: configStorageKey) {
            return try? JSONDecoder().decode(AgentServiceConfig.self, from: data)
        }
        if let data = UserDefaults.standard.data(forKey: "agent.service.config.v2") {
            return try? JSONDecoder().decode(AgentServiceConfig.self, from: data)
        }
        if let data = UserDefaults.standard.data(forKey: "agent.service.config.v1") {
            return try? JSONDecoder().decode(AgentServiceConfig.self, from: data)
        }
        return nil
    }

    private static func saveConfig(_ config: AgentServiceConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: configStorageKey)
    }
}
