import Foundation
import SwiftHarnessAgent

/// Built-in subagent definitions and a factory that wires them into a
/// `TaskCoordinator`. We keep the registry intentionally small for now —
/// just an `explore` read-only scout — and grow it from here when the user
/// gains a way to author custom subagents.
///
/// Per-session: each `SessionAgent` owns its own coordinator so working
/// directory + execution policy stay in sync with the session's project.
enum TaskSubagentCatalog {
    /// Read-only scout. No write/edit/bash; just `read`. Returns compressed
    /// findings to the parent agent.
    static let exploreDefinition = SubagentDefinition(
        id: "explore",
        displayName: "Explorer",
        description: "Read-only investigator that returns compressed context",
        systemPrompt: """
        You are a read-only codebase scout. Investigate the user's repository \
        using the `read` tool only. Return concise, actionable findings.

        Rules:
        - Do not attempt to write, edit, or run shell commands.
        - Cite file paths and line ranges when summarizing what you found.
        - Be brief. The parent agent will follow up if needed.
        """,
        tools: [ReadTool()],
        skills: [],
        maxSteps: 8
    )

    /// All built-in definitions. Order matters: it's the order surfaced in
    /// the tool description so the model sees `explore` first.
    static let builtins: [SubagentDefinition] = [exploreDefinition]

    /// Build a coordinator for a single `SessionAgent`. The model factory
    /// reuses the parent session's chat config so subagents talk to the
    /// same provider as the user-facing chat.
    static func makeCoordinator(
        config: AgentServiceConfig,
        workingDirectory: URL,
        executionPolicy: ToolExecutionPolicy,
        maxConcurrency: Int = 4
    ) -> TaskCoordinator {
        let baseURL = URL(string: config.baseURL) ?? URL(string: "http://127.0.0.1:11434/v1")!

        return TaskCoordinator(
            definitions: builtins,
            modelFactory: { _ in
                AgentSDKFactory.makeChatModel(config: config, baseURL: baseURL)
            },
            workingDirectory: workingDirectory,
            executionPolicy: executionPolicy,
            maxConcurrency: maxConcurrency
        )
    }
}
