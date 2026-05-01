import Foundation
import SwiftCodingAgent

/// Pure factory for `AgentSDK` instances. No state — every call builds a
/// fresh SDK from the current config + project path + sandbox roots + skills.
///
/// Pulling this out of `AgentManager` makes it possible to unit-test the
/// SDK wiring (allowed roots, tool execution policy, system prompt) without
/// spinning up the whole singleton.
enum AgentSDKFactory {
    static func make(
        config: AgentServiceConfig,
        activeProjectPath: String?,
        storageDirectoryURL: URL,
        defaultExecutionWorkspaceURL: URL,
        sandboxRoots: [URL]
    ) -> AgentSDK {
        let baseURL = URL(string: config.baseURL) ?? URL(string: "http://127.0.0.1:11434/v1")!
        let resolvedProjectPath = activeProjectPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let workingDirectoryURL = resolvedProjectPath.isEmpty
            ? defaultExecutionWorkspaceURL
            : URL(fileURLWithPath: resolvedProjectPath)

        var allowedRoots = [workingDirectoryURL]
        for root in sandboxRoots where !allowedRoots.contains(where: { $0.standardizedFileURL.path == root.standardizedFileURL.path }) {
            allowedRoots.append(root)
        }

        var skillsDirs: [URL] = []
        if let bundledSkills = Bundle.main.resourceURL?.appendingPathComponent("skills", isDirectory: true) {
            skillsDirs.append(bundledSkills)
        }
        skillsDirs.append(storageDirectoryURL.agentSkillsDirectory())

        let fileToolPolicy = ToolExecutionPolicy(allowedRoots: allowedRoots, bash: .disabled)
        let bashToolPolicy = ToolExecutionPolicy(allowedRoots: allowedRoots, bash: .unrestricted)
        let toolExecutionContexts: [String: ToolExecutionContext] = [
            "read": ToolExecutionContext(workingDirectory: workingDirectoryURL, executionPolicy: fileToolPolicy),
            "write": ToolExecutionContext(workingDirectory: workingDirectoryURL, executionPolicy: fileToolPolicy),
            "edit": ToolExecutionContext(workingDirectory: workingDirectoryURL, executionPolicy: fileToolPolicy),
            "bash": ToolExecutionContext(workingDirectory: workingDirectoryURL, executionPolicy: bashToolPolicy)
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
                    systemPrompt: defaultSystemPrompt
                )
            ],
            tools: [],
            workingDirectory: workingDirectoryURL,
            allowedRoots: allowedRoots,
            executionPolicy: ToolExecutionPolicy(allowedRoots: allowedRoots, bash: .disabled),
            toolExecutionContexts: toolExecutionContexts,
            maxSteps: nil,
            skillsDirectories: skillsDirs,
            approvalHandler: { request in
                await ToolApprovalCenter.shared.request(request)
            }
        )
    }

    private static let defaultSystemPrompt = """
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
}
