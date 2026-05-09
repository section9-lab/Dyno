import Foundation
import SwiftHarnessAgent

/// Pure factory for `AgentSDK` instances. No state — every call builds a
/// fresh SDK from the current config + project path + sandbox roots + skills
/// + per-session productivity dependencies.
///
/// Pulling this out of `AgentManager` makes it possible to unit-test the
/// SDK wiring (allowed roots, tool execution policy, system prompt) without
/// spinning up the whole singleton.
enum AgentSDKFactory {
    /// Bundle of dependencies the productivity tools need. These live one
    /// instance per `SessionAgent` so each session has its own todo list,
    /// ask channel, and subagent coordinator.
    struct ProductivityDependencies {
        let todoStore: TodoStore
        let askHandler: AskHandler
        let taskCoordinator: TaskCoordinator
    }

    /// Working directory + execution policy resolved from the session's
    /// project path + sandbox roots. The caller may want them to build a
    /// `TaskCoordinator` whose subagents operate inside the same boundary.
    struct ResolvedExecutionScope {
        let workingDirectory: URL
        let allowedRoots: [URL]
        let fileToolPolicy: ToolExecutionPolicy
        let bashToolPolicy: ToolExecutionPolicy
    }

    static func resolveExecutionScope(
        activeProjectPath: String?,
        defaultExecutionWorkspaceURL: URL,
        sandboxRoots: [URL]
    ) -> ResolvedExecutionScope {
        let resolvedProjectPath = activeProjectPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let workingDirectoryURL = resolvedProjectPath.isEmpty
            ? defaultExecutionWorkspaceURL
            : URL(fileURLWithPath: resolvedProjectPath)

        var allowedRoots = [workingDirectoryURL]
        for root in sandboxRoots where !allowedRoots.contains(where: { $0.standardizedFileURL.path == root.standardizedFileURL.path }) {
            allowedRoots.append(root)
        }

        return ResolvedExecutionScope(
            workingDirectory: workingDirectoryURL,
            allowedRoots: allowedRoots,
            fileToolPolicy: ToolExecutionPolicy(allowedRoots: allowedRoots, bash: .disabled),
            bashToolPolicy: ToolExecutionPolicy(allowedRoots: allowedRoots, bash: .unrestricted)
        )
    }

    static func make(
        config: AgentServiceConfig,
        activeProjectPath: String?,
        storageDirectoryURL: URL,
        defaultExecutionWorkspaceURL: URL,
        sandboxRoots: [URL],
        productivity: ProductivityDependencies
    ) -> AgentSDK {
        let baseURL = URL(string: config.baseURL) ?? URL(string: "http://127.0.0.1:11434/v1")!
        let scope = resolveExecutionScope(
            activeProjectPath: activeProjectPath,
            defaultExecutionWorkspaceURL: defaultExecutionWorkspaceURL,
            sandboxRoots: sandboxRoots
        )

        var skillsDirs: [URL] = []
        if let bundledSkills = Bundle.main.resourceURL?.appendingPathComponent("skills", isDirectory: true) {
            skillsDirs.append(bundledSkills)
        }
        skillsDirs.append(storageDirectoryURL.agentSkillsDirectory())

        let toolExecutionContexts: [String: ToolExecutionContext] = [
            "read": ToolExecutionContext(workingDirectory: scope.workingDirectory, executionPolicy: scope.fileToolPolicy),
            "write": ToolExecutionContext(workingDirectory: scope.workingDirectory, executionPolicy: scope.fileToolPolicy),
            "edit": ToolExecutionContext(workingDirectory: scope.workingDirectory, executionPolicy: scope.fileToolPolicy),
            "bash": ToolExecutionContext(workingDirectory: scope.workingDirectory, executionPolicy: scope.bashToolPolicy)
        ]

        return AgentSDK(
            client: makeLLMClient(config: config, baseURL: baseURL),
            modelName: config.modelId,
            skills: [
                BasicSkill(
                    name: "default",
                    systemPrompt: defaultSystemPrompt
                )
            ],
            tools: [],
            workingDirectory: scope.workingDirectory,
            allowedRoots: scope.allowedRoots,
            executionPolicy: ToolExecutionPolicy(allowedRoots: scope.allowedRoots, bash: .disabled),
            toolExecutionContexts: toolExecutionContexts,
            maxSteps: nil,
            skillsDirectories: skillsDirs,
            approvalHandler: { request in
                await ToolApprovalCenter.shared.request(request)
            },
            parallelToolCalls: true,
            todoStore: productivity.todoStore,
            askHandler: productivity.askHandler,
            taskCoordinator: productivity.taskCoordinator
        )
    }

    /// Builds the concrete `LLMClient` that owns the wire-format details
    /// (request shape, auth header, streaming parser). Routing is driven
    /// purely by `config.apiKind` — add a new case here when wiring up a
    /// brand-new protocol (e.g. Bedrock, Vertex).
    ///
    /// `internal` so `TaskSubagentCatalog` can reuse the same client
    /// configuration when spawning subagents.
    static func makeLLMClient(config: AgentServiceConfig, baseURL: URL) -> any LLMClient {
        let apiKey = config.apiKey.isEmpty ? nil : config.apiKey
        switch config.apiKind {
        case .anthropicMessages:
            // Anthropic's REST endpoint lives at `/v1/messages`; users
            // typically configure the provider with `https://api.anthropic.com/v1`
            // already, and `AnthropicMessagesClient` appends the `messages` segment
            // itself, so we hand it the base unchanged.
            return AnthropicMessagesClient(
                baseURL: baseURL,
                apiKey: apiKey,
                timeout: 300
            )
        case .openAICompletions:
            return OpenAIChatCompletionsClient(
                baseURL: baseURL,
                apiKey: apiKey,
                timeout: 300
            )
        case .googleGenerativeLanguage:
            // Gemini's endpoint is `/v1beta/models/{model}:generateContent`;
            // `GoogleGenerativeAIClient` builds that path itself, so we hand
            // it the base (typically `https://generativelanguage.googleapis.com/v1beta`)
            // unchanged. Auth is via `x-goog-api-key`, not Bearer.
            return GoogleGenerativeAIClient(
                baseURL: baseURL,
                apiKey: apiKey,
                timeout: 300
            )
        }
    }

    private static let defaultSystemPrompt = """
You are a coding assistant. You help users write, debug, and understand code.

You have access to these tools:
- read: Read files and directories
- write: Create or overwrite files
- edit: Make precise edits to existing files
- bash: Run shell commands
- todo_write: Track multi-step work as a phased task list. Use it whenever a job has 3+ distinct steps. Mark a task `done` immediately after finishing.
- ask: Ask the user a clarifying question only when multiple approaches have materially different tradeoffs the user must decide. Default to action when defaults exist.
- task: Spawn one or more `explore` subagents in parallel to fan out read-only investigations. Each task must be self-contained.

Work directly in the user's project when one is selected. Read files to understand context before making changes. Use bash to run tests, linters, and other development tools.

When a task matches a skill, use the read tool to load the skill's SKILL.md file for detailed instructions, then follow them carefully.

Think step by step. If you're unsure, read more files or ask the user.
"""
}
