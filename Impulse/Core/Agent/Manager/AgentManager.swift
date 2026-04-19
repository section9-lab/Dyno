import Foundation
import Combine
import SwiftUI
import SwiftCodingAgent

@MainActor
final class AgentManager: ObservableObject {
    enum ProjectDirectoryCheckStatus {
        case idle
        case info
        case success
        case failure
    }

    static let shared = AgentManager()

    @Published var isResponding: Bool = false
    @Published var isServiceConnected: Bool = false
    @Published var connectionStatusText: String = "模型服务检测中..."
    @Published var config: AgentServiceConfig
    @Published var latestToolExecutions: [AgentToolExecution] = []
    @Published var latestCompactionSummary: String?
    @Published var projectDirectoryCheckMessage: String = ""
    @Published var projectDirectoryCheckStatus: ProjectDirectoryCheckStatus = .idle

    let registry = ModelRegistry.shared

    var agentHomeDirectoryURL: URL {
        URL(fileURLWithPath: resolvedAgentHomeDirectoryPath)
    }

    var projectDirectoryURL: URL? {
        let path = resolvedProjectDirectoryPath
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    var executionWorkingDirectoryURL: URL {
        projectDirectoryURL ?? Self.defaultExecutionWorkspaceURL
    }

    private var resolvedAgentHomeDirectoryPath: String {
        Self.resolvedAgentHomeDirectoryPath(for: config)
    }

    private var resolvedProjectDirectoryPath: String {
        Self.resolvedProjectDirectoryPath(for: config)
    }

    private static var defaultExecutionWorkspaceURL: URL {
        URL(fileURLWithPath: AgentServiceConfig.defaultExecutionWorkspacePath)
    }

    private static func resolvedAgentHomeDirectoryPath(for config: AgentServiceConfig) -> String {
        let path = config.agentHomeDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? AgentServiceConfig.defaultAgentHomeDirectoryPath : path
    }

    private static func resolvedProjectDirectoryPath(for config: AgentServiceConfig) -> String {
        config.projectDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let configStorageKey = "agent.service.config.v3"

    private var sdk: AgentSDK
    private let sandboxAccess = SandboxAccessManager.shared
    private let sessionStore: AgentSessionStoring = AgentSessionStore()
    private var migratedLegacyAgentDataKeys: Set<String> = []

    private init() {
        let initialConfig = Self.loadConfig() ?? Self.defaultConfigFromEnvironment()
        self.config = initialConfig
        self.sdk = Self.makeSDK(config: initialConfig)

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
        projectDirectoryCheckMessage = ""
        projectDirectoryCheckStatus = .idle

        registry.setApiKey(newConfig.apiKey, for: newConfig.providerId)

        Self.saveConfig(newConfig)
        refreshRuntimeContext()
        await refreshServiceStatus()
    }

    func refreshRuntimeContext() {
        _ = sandboxAccess.authorizedRoots.count
        latestCompactionSummary = nil
        bootstrapAgentDirectory()
        migrateLegacyAgentDataIfNeeded()
        sdk = Self.makeSDK(config: config)
    }

    private func bootstrapAgentDirectory() {
        let agentHomeDirectoryURL = agentHomeDirectoryURL
        let sessionDir = agentHomeDirectoryURL.agentSessionDirectory()
        let skillsDir = agentHomeDirectoryURL.agentSkillsDirectory()
        let memoryDir = agentHomeDirectoryURL.agentMemoryDirectory()

        for dir in [agentHomeDirectoryURL, sessionDir, skillsDir, memoryDir, Self.defaultExecutionWorkspaceURL] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private func migrateLegacyAgentDataIfNeeded() {
        guard let projectDirectoryURL else { return }

        let legacyAgentDirectory = projectDirectoryURL.appendingPathComponent(".agent", isDirectory: true)
        let targetAgentDirectory = agentHomeDirectoryURL
        guard legacyAgentDirectory.standardizedFileURL.path != targetAgentDirectory.standardizedFileURL.path else { return }

        let migrationKey = [legacyAgentDirectory.standardizedFileURL.path, targetAgentDirectory.standardizedFileURL.path].joined(separator: "->")
        guard !migratedLegacyAgentDataKeys.contains(migrationKey) else { return }
        migratedLegacyAgentDataKeys.insert(migrationKey)

        copyDirectoryContentsIfNeeded(from: legacyAgentDirectory.appendingPathComponent("session", isDirectory: true), to: targetAgentDirectory.agentSessionDirectory())
        copyDirectoryContentsIfNeeded(from: legacyAgentDirectory.appendingPathComponent("skills", isDirectory: true), to: targetAgentDirectory.agentSkillsDirectory())
    }

    private func copyDirectoryContentsIfNeeded(from source: URL, to destination: URL) {
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        let existing = (try? FileManager.default.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        guard existing.isEmpty else { return }

        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let items = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil, options: [])
            for item in items {
                let target = destination.appendingPathComponent(item.lastPathComponent, isDirectory: false)
                guard !FileManager.default.fileExists(atPath: target.path) else { continue }
                try FileManager.default.copyItem(at: item, to: target)
            }
        } catch {
            print("Failed to import legacy agent data from \(source.path): \(error)")
        }
    }

    func refreshServiceStatus() async {
        connectionStatusText = "正在检测模型服务..."

        guard !config.baseURL.isEmpty else {
            isServiceConnected = false
            connectionStatusText = "❌ Base URL 未配置"
            return
        }

        await registry.discoverLiveModels(for: config.providerId)

        let provider = registry.provider(for: config.providerId)
        let liveModels = provider?.models.filter(\.isLive) ?? []

        if liveModels.isEmpty {
            guard let baseURL = URL(string: config.baseURL) else {
                isServiceConnected = false
                connectionStatusText = "❌ Base URL 无效"
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
                    connectionStatusText = "✅ 已连接（\(config.modelId)）"
                } else {
                    isServiceConnected = false
                    connectionStatusText = "❌ 服务不可用"
                }
            } catch {
                isServiceConnected = false
                connectionStatusText = "❌ 连接失败：\(error.localizedDescription)"
            }
            return
        }

        isServiceConnected = true
        let found = liveModels.contains { $0.id == config.modelId }
        connectionStatusText = found
            ? "✅ 已连接（\(config.modelId)）"
            : "⚠️ 已连接（\(liveModels.count) 个模型），但未发现 \(config.modelId)"
    }

    // MARK: - Project Directory

    func verifyProjectDirectoryAccess() async {
        guard let projectDirectoryURL else {
            projectDirectoryCheckStatus = .info
            projectDirectoryCheckMessage = "ℹ️ 未设置项目目录；执行时将使用默认工作目录。"
            return
        }

        let probeDir = projectDirectoryURL.appendingPathComponent(".impulse_project_probe", isDirectory: true)
        let probeFile = probeDir.appendingPathComponent("probe.txt")

        do {
            try FileManager.default.createDirectory(at: probeDir, withIntermediateDirectories: true)
            let content = "probe at \(Date())"
            try content.write(to: probeFile, atomically: true, encoding: .utf8)
            _ = try String(contentsOf: probeFile, encoding: .utf8)
            try? FileManager.default.removeItem(at: probeFile)
            try? FileManager.default.removeItem(at: probeDir)
            projectDirectoryCheckStatus = .success
            projectDirectoryCheckMessage = "✅ 项目目录可读写：\(projectDirectoryURL.path)"
        } catch {
            projectDirectoryCheckStatus = .failure
            projectDirectoryCheckMessage = mapToUserFriendlySandboxMessage(error.localizedDescription)
        }
    }

    // MARK: - Agent session persistence

    func loadPersistedConversations() -> [SessionConversationSnapshot] {
        (try? sessionStore.load(agentHomeDirectory: resolvedAgentHomeDirectoryPath)) ?? []
    }

    func persistConversations(_ conversations: [SessionConversationSnapshot]) {
        do {
            try sessionStore.save(
                conversations: conversations,
                agentHomeDirectory: resolvedAgentHomeDirectoryPath,
                projectDirectory: executionWorkingDirectoryURL.path
            )
        } catch {
            print("Failed to persist session snapshots: \(error)")
        }
    }

    // MARK: - Agent execution

    func chat(prompt: String, contextPrelude: String? = nil) async throws -> String {
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

            let text = result.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                if !latestToolExecutions.isEmpty {
                    return "本轮已执行 \(latestToolExecutions.count) 次工具调用。请继续让我完成最后一步。"
                }
                return "(模型返回空内容)"
            }
            return text
        } catch AgentLoopError.maxStepsReached {
            let allMessages = await sdk.history()
            let runMessages = Array(allMessages.dropFirst(historyCountBefore))
            latestToolExecutions = extractToolExecutions(from: runMessages)
            latestCompactionSummary = await sdk.compactionSummary()?.trimmingCharacters(in: .whitespacesAndNewlines)

            if let lastAssistant = runMessages.last(where: { $0.role == .assistant }),
               !lastAssistant.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return lastAssistant.content
            }

            return "我已经执行到步骤上限（\(latestToolExecutions.count) 次工具调用），还差最后收敛。你可以回复「继续」，我会基于当前上下文接着完成。"
        }
    }

    private func signature(for executions: [AgentToolExecution]) -> String {
        executions.map { "\($0.id)|\($0.status.rawValue)|\($0.summary)" }.joined(separator: "||")
    }

    private func extractToolExecutions(from messages: [AgentMessage]) -> [AgentToolExecution] {
        let trackedTools: Set<String> = ["read", "write", "edit", "bash"]

        var argumentsByCallID: [String: String] = [:]
        for message in messages where message.role == .assistant {
            guard let callID = message.toolCallID,
                  let args = message.toolArgumentsJSON,
                  let name = message.toolName,
                  trackedTools.contains(name)
            else { continue }
            argumentsByCallID[callID] = args
        }

        return messages.enumerated().compactMap { index, message in
            guard message.role == .tool,
                  let name = message.toolName,
                  trackedTools.contains(name)
            else { return nil }

            let output = message.content
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let failed = trimmed.hasPrefix("ERROR:")
            let stableID = message.toolCallID ?? "\(name)-\(index)"
            let argsJSON = message.toolCallID.flatMap { argumentsByCallID[$0] }
            let summary = buildToolSummary(toolName: name, argumentsJSON: argsJSON)
            let displayOutput = failed ? mapToUserFriendlySandboxMessage(trimmed) + "\n\n原始错误:\n\(trimmed)" : output

            return AgentToolExecution(
                id: stableID,
                toolName: name,
                status: failed ? .failed : .success,
                summary: summary,
                output: displayOutput
            )
        }
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
            return "❌ 目标路径超出当前项目或授权目录范围。请添加目录授权，或把操作限制在项目目录内。"
        }
        if lower.contains("operation not permitted") || lower.contains("permission denied") {
            return "❌ 当前执行环境拒绝访问该路径。请检查项目目录和授权目录配置。"
        }
        if lower.contains("no such file") || lower.contains("cannot read file") {
            return "❌ 文件不存在或不可访问。请确认路径正确，并且目录已被授权。"
        }
        return "❌ 操作失败：\(raw)"
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
        return latestCompactionSummary
    }

    private static func makeSDK(config: AgentServiceConfig) -> AgentSDK {
        let baseURL = URL(string: config.baseURL) ?? URL(string: "http://127.0.0.1:11434/v1")!
        let agentHomeDirectoryURL = URL(fileURLWithPath: resolvedAgentHomeDirectoryPath(for: config))
        let projectDirectoryPath = resolvedProjectDirectoryPath(for: config)
        let workingDirectoryURL = projectDirectoryPath.isEmpty
            ? defaultExecutionWorkspaceURL
            : URL(fileURLWithPath: projectDirectoryPath)

        let sandboxRoots = SandboxAccessManager.shared.authorizedRoots
        var allowedRoots = [workingDirectoryURL]
        for root in sandboxRoots where !allowedRoots.contains(where: { $0.standardizedFileURL.path == root.standardizedFileURL.path }) {
            allowedRoots.append(root)
        }

        var skillsDirs: [URL] = []
        if let bundledSkills = Bundle.main.resourceURL?.appendingPathComponent("skills", isDirectory: true) {
            skillsDirs.append(bundledSkills)
        }
        skillsDirs.append(agentHomeDirectoryURL.agentSkillsDirectory())

        let allTools: [any AgentTool] = []
        let fileToolPolicy = ToolExecutionPolicy(
            allowedRoots: allowedRoots,
            bash: .disabled
        )
        let bashToolPolicy = ToolExecutionPolicy(
            allowedRoots: allowedRoots,
            bash: .sandboxed(.init())
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
            maxSteps: 16,
            skillsDirectories: skillsDirs
        )
    }

    private static func defaultConfigFromEnvironment() -> AgentServiceConfig {
        let base = ProcessInfo.processInfo.environment["OPENAI_BASE_URL"] ?? "http://127.0.0.1:11434/v1"
        let model = ProcessInfo.processInfo.environment["OPENAI_MODEL"]
            ?? ProcessInfo.processInfo.environment["OLLAMA_MODEL"]
            ?? ""
        let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
        let agentHomeDirectory =
            ProcessInfo.processInfo.environment["AGENT_HOME_DIRECTORY"]
            ?? AgentServiceConfig.defaultAgentHomeDirectoryPath
        let projectDirectory =
            ProcessInfo.processInfo.environment["AGENT_PROJECT_DIRECTORY"]
            ?? ProcessInfo.processInfo.environment["AGENT_SANDBOX_DIRECTORY"]
            ?? ProcessInfo.processInfo.environment["AGENT_WORKSPACE"]
            ?? ProcessInfo.processInfo.environment["AGENT_WORKDIR"]
            ?? ""

        let providerId = base.contains("11434") ? "ollama" : "custom"
        return AgentServiceConfig(
            providerId: providerId,
            baseURL: base,
            apiKey: key,
            modelId: model,
            agentHomeDirectory: agentHomeDirectory,
            projectDirectory: projectDirectory
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
