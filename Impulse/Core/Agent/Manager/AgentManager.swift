import Foundation
import Combine
import SwiftUI
import SwiftAgent

@MainActor
final class AgentManager: ObservableObject {
    static let shared = AgentManager()

    @Published var isResponding: Bool = false
    @Published var isServiceConnected: Bool = false
    @Published var connectionStatusText: String = "模型服务检测中..."
    @Published var config: AgentServiceConfig
    @Published var latestToolExecutions: [AgentToolExecution] = []
    @Published var latestCompactionSummary: String?
    @Published var workspaceCheckMessage: String = ""

    let registry = ModelRegistry.shared

    private static let configStorageKey = "agent.service.config.v2"

    private var sdk: AgentSDK
    private let sandboxAccess = SandboxAccessManager.shared
    private let sessionStore: AgentSessionStoring = AgentSessionStore()

    private init() {
        let initialConfig = Self.loadConfig() ?? Self.defaultConfigFromEnvironment()
        self.config = initialConfig
        self.sdk = Self.makeSDK(config: initialConfig)

        // Sync API key from config into registry
        registry.setApiKey(initialConfig.apiKey, for: initialConfig.providerId)

        Task {
            await registry.refresh()
            await self.refreshServiceStatus()
        }
    }

    func applyConfig(_ newConfig: AgentServiceConfig) async {
        config = newConfig
        latestToolExecutions = []
        latestCompactionSummary = nil
        workspaceCheckMessage = ""

        // Sync API key into registry
        registry.setApiKey(newConfig.apiKey, for: newConfig.providerId)

        Self.saveConfig(newConfig)
        refreshRuntimeContext()
        await refreshServiceStatus()
    }

    func refreshRuntimeContext() {
        _ = sandboxAccess.authorizedRoots.count
        latestCompactionSummary = nil
        sdk = Self.makeSDK(config: config)
        bootstrapAgentDirectory()
    }

    private func bootstrapAgentDirectory() {
        let workspace = config.workspace.isEmpty
            ? FileManager.default.homeDirectoryForCurrentUser.path
            : config.workspace
        let workspaceURL = URL(fileURLWithPath: workspace)
        let sessionDir = workspaceURL.agentSessionDirectory()
        let skillsDir = workspaceURL.agentSkillsDirectory()

        for dir in [sessionDir, skillsDir] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    func refreshServiceStatus() async {
        connectionStatusText = "正在检测模型服务..."

        guard !config.baseURL.isEmpty else {
            isServiceConnected = false
            connectionStatusText = "❌ Base URL 未配置"
            return
        }

        // Use ModelRegistry to discover live models
        await registry.discoverLiveModels(for: config.providerId)

        let provider = registry.provider(for: config.providerId)
        let liveModels = provider?.models.filter(\.isLive) ?? []

        if liveModels.isEmpty {
            // Fallback: direct connectivity check
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

    // MARK: - Runtime / Workspace

    func verifyWorkspaceAccess() async {
        let workspace = config.workspace.isEmpty ? FileManager.default.homeDirectoryForCurrentUser.path : config.workspace
        let workspaceURL = URL(fileURLWithPath: workspace)
        let probeDir = workspaceURL.appendingPathComponent(".impulse_sandbox_probe", isDirectory: true)
        let probeFile = probeDir.appendingPathComponent("probe.txt")

        do {
            try FileManager.default.createDirectory(at: probeDir, withIntermediateDirectories: true)
            let content = "probe at \(Date())"
            try content.write(to: probeFile, atomically: true, encoding: .utf8)
            _ = try String(contentsOf: probeFile, encoding: .utf8)
            try? FileManager.default.removeItem(at: probeFile)
            try? FileManager.default.removeItem(at: probeDir)
            workspaceCheckMessage = "✅ Workspace 可读写：\(workspace)"
        } catch {
            workspaceCheckMessage = mapToUserFriendlySandboxMessage(error.localizedDescription)
        }
    }

    // MARK: - Agent session persistence

    func loadPersistedConversations() -> [SessionConversationSnapshot] {
        (try? sessionStore.load(workspace: config.workspace)) ?? []
    }

    func persistConversations(_ conversations: [SessionConversationSnapshot]) {
        do {
            try sessionStore.save(conversations: conversations, workspace: config.workspace)
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
            return "❌ 目标路径超出授权目录范围。请将目标目录加入沙箱权限，或把操作限制在 Workspace 内。"
        }
        if lower.contains("operation not permitted") || lower.contains("permission denied") {
            return "❌ 沙箱拒绝访问该路径。请在模型设置的沙箱权限中添加目录授权后重试。"
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
        let workspace = config.workspace.isEmpty ? FileManager.default.homeDirectoryForCurrentUser.path : config.workspace
        let workspaceURL = URL(fileURLWithPath: workspace)

        let sandboxRoots = SandboxAccessManager.shared.authorizedRoots
        var allowedRoots = [workspaceURL]
        for root in sandboxRoots where !allowedRoots.contains(where: { $0.standardizedFileURL.path == root.standardizedFileURL.path }) {
            allowedRoots.append(root)
        }

        // 1. Bundled skills (shipped with app, always available)
        var skillsDirs: [URL] = []
        if let bundledSkills = Bundle.main.resourceURL?.appendingPathComponent("skills", isDirectory: true) {
            skillsDirs.append(bundledSkills)
        }

        // 2. User workspace skills: {workspace}/.agent/skills/
        skillsDirs.append(workspaceURL.agentSkillsDirectory())

        let allTools: [any AgentTool] = []

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

Work directly in the user's project. Read files to understand context before making changes. Use bash to run tests, linters, and other development tools.

When a task matches a skill, use the read tool to load the skill's SKILL.md file for detailed instructions, then follow them carefully.

Think step by step. If you're unsure, read more files or ask the user.
"""
                )
            ],
            tools: allTools,
            workingDirectory: workspaceURL,
            allowedRoots: allowedRoots,
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
        let workspace =
            ProcessInfo.processInfo.environment["AGENT_WORKSPACE"]
            ?? ProcessInfo.processInfo.environment["AGENT_WORKDIR"]
            ?? FileManager.default.homeDirectoryForCurrentUser.path

        let providerId = base.contains("11434") ? "ollama" : "custom"
        return AgentServiceConfig(providerId: providerId, baseURL: base, apiKey: key, modelId: model, workspace: workspace)
    }

    private static func loadConfig() -> AgentServiceConfig? {
        // Try new format first
        if let data = UserDefaults.standard.data(forKey: configStorageKey) {
            return try? JSONDecoder().decode(AgentServiceConfig.self, from: data)
        }
        // Migrate from old format
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
