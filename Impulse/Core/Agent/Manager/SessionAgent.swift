import Foundation
import Combine
import SwiftUI
import SwiftCodingAgent

/// Per-session agent state and SDK.
/// Each chat session owns one of these so multiple sessions can run in parallel
/// without sharing conversation history or polluting each other's tool runs.
@MainActor
final class SessionAgent: ObservableObject, Identifiable {
    let id: String          // sessionID
    let projectPath: String

    @Published var isResponding: Bool = false
    @Published var latestToolExecutions: [AgentToolExecution] = []
    @Published var latestCompactionSummary: String?
    @Published var contextUsage: ContextUsage = ContextUsage(usedTokens: 0, totalTokens: 128_000, reservedTokens: 16_384)

    private var sdk: AgentSDK
    /// Tracks the in-flight chat/compact Task so callers can cancel it
    /// (e.g. when the session is deleted or the app is shutting down).
    private var currentTask: Task<Void, Never>?

    init(id: String, projectPath: String, sdk: AgentSDK) {
        self.id = id
        self.projectPath = projectPath
        self.sdk = sdk
    }

    func replaceSDK(_ newSDK: AgentSDK) {
        sdk = newSDK
        latestToolExecutions = []
        latestCompactionSummary = nil
    }

    /// Register the outer Task that's awaiting `sendChat` / `compact`,
    /// so `cancel()` can interrupt it.
    func registerCurrentTask(_ task: Task<Void, Never>) {
        currentTask = task
    }

    /// Cancels any in-flight chat/compact task. Safe to call when idle.
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isResponding = false
    }

    func sendChat(prompt: String, contextPrelude: String? = nil) async throws -> String {
        isResponding = true
        latestToolExecutions = []
        latestCompactionSummary = nil
        defer {
            isResponding = false
            // Manager may have a pending SDK rebuild deferred from mid-run.
            AgentManager.shared.applyPendingConfigRebuild(for: id)
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

    func compact(customInstructions: String? = nil) async throws -> String? {
        isResponding = true
        latestToolExecutions = []
        defer {
            isResponding = false
            AgentManager.shared.applyPendingConfigRebuild(for: id)
        }

        let summary = try await sdk.compact(customInstructions: customInstructions)
        latestCompactionSummary = summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        contextUsage = await sdk.contextUsage()
        return latestCompactionSummary
    }

    func refreshContextUsage() async {
        contextUsage = await sdk.contextUsage()
    }

    // MARK: - Tool execution extraction (private)

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
}
