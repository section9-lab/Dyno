import Foundation
import Combine
import SwiftUI
import SwiftHarnessAgent

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

    /// Live-accumulated assistant text for the in-flight turn. Cleared when a
    /// new chat starts and reset to empty when the run finishes (the final
    /// answer is persisted via `ChatViewModel`).
    @Published var liveAssistantText: String = ""
    /// Live-accumulated reasoning / chain-of-thought for the in-flight turn.
    /// Surfaced in a collapsed pane so the user can see the model "thinking"
    /// without it polluting the final answer.
    @Published var liveReasoningText: String = ""

    /// Live mirror of `todoStore`'s phases. Updated on every store mutation
    /// via the long-running `phasesObservation` task.
    @Published var todoPhases: [TodoPhase] = []

    /// Per-session todo list. Persisted via `StoredTodoSnapshot` (see
    /// `ChatViewModel.persistRunResults` and the load path in
    /// `AgentManager.sessionAgent(for:projectPath:)`).
    let todoStore: TodoStore

    /// Per-session subagent coordinator. Owns the explore subagent and
    /// inherits this session's working directory + execution policy. The
    /// coordinator is rebuilt only when the agent is rebuilt wholesale
    /// (project change / new chat); plain config refresh keeps it.
    let taskCoordinator: TaskCoordinator

    private var sdk: AgentSDK
    /// Tracks the in-flight chat/compact Task so callers can cancel it
    /// (e.g. when the session is deleted or the app is shutting down).
    private var currentTask: Task<Void, Never>?
    /// Long-running observation of `todoStore.phasesStream()`. Owned here so
    /// it lives as long as the SessionAgent does and is cancelled in
    /// `cancel()`.
    private var phasesObservation: Task<Void, Never>?
    /// Set to `true` after the persisted todo snapshot has been loaded
    /// into `todoStore`. Idempotent guard so callers can drive seeding
    /// from multiple lifecycle hooks (selectSession, sendMessage, view
    /// onAppear) without trampling live in-memory state.
    private(set) var hasSeededTodos: Bool = false

    init(
        id: String,
        projectPath: String,
        sdk: AgentSDK,
        todoStore: TodoStore,
        taskCoordinator: TaskCoordinator
    ) {
        self.id = id
        self.projectPath = projectPath
        self.sdk = sdk
        self.todoStore = todoStore
        self.taskCoordinator = taskCoordinator

        startTodoObservation()
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
    /// Also cancels the todo-phases observation task; call this exactly
    /// once when the SessionAgent is being discarded.
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        phasesObservation?.cancel()
        phasesObservation = nil
        isResponding = false
    }

    /// Replace the persisted todo phases on disk into the live store.
    /// Called when a session is selected and we want to seed the indicator
    /// with the snapshot from SwiftData. Mirrors `op: "init"` semantically
    /// but doesn't go through the tool — the agent never sees this.
    func loadTodoSnapshot(_ phases: [TodoPhase]) async {
        await todoStore.replaceExternal(phases)
        hasSeededTodos = true
    }

    func sendChat(prompt: String, contextPrelude: String? = nil) async throws -> String {
        isResponding = true
        latestToolExecutions = []
        latestCompactionSummary = nil
        liveAssistantText = ""
        liveReasoningText = ""
        defer {
            isResponding = false
            // NOTE: don't wipe liveAssistantText / liveReasoningText here —
            // the caller (ChatViewModel.persistRunResults) reads
            // liveReasoningText immediately after `sendChat` returns to
            // persist it on the StoredMessage. The next chat run resets both
            // at its top, so leaking them across runs is fine; AgentResponseView
            // only renders live content while isResponding is true anyway.
            AgentManager.shared.applyPendingConfigRebuild(for: id)
        }

        let historyCountBefore = await sdk.history().count

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

        var assembledFinalText = ""
        var finalResult: AgentRunResult?
        var lastToolSignature = ""

        // Throttle live UI updates. The model can emit dozens of textDeltas
        // per second; pushing each one straight into a `@Published` property
        // forces SwiftUI (and MarkdownUI's cmark-gfm reparse) to redraw on
        // every token, saturating the main thread and stealing scroll-wheel
        // events. We accumulate deltas in plain locals and flush to the
        // @Published mirrors at most every `flushInterval`. The final flush
        // happens on `.completed` (or via the `defer`-equivalent below) so no
        // tail tokens are lost.
        let flushInterval: TimeInterval = 0.1
        var pendingAssistant = ""
        var pendingReasoning = ""
        var lastFlush = Date()

        @MainActor func flushIfDue(force: Bool = false) {
            let now = Date()
            guard force || now.timeIntervalSince(lastFlush) >= flushInterval else { return }
            if !pendingAssistant.isEmpty {
                liveAssistantText += pendingAssistant
                pendingAssistant = ""
            }
            if !pendingReasoning.isEmpty {
                liveReasoningText += pendingReasoning
                pendingReasoning = ""
            }
            lastFlush = now
        }
        do {
            for try await event in sdk.runStream(prompt: effectivePrompt) {
                try Task.checkCancellation()

                switch event {
                case .stepStarted:
                    // Each new step: clear live text so deltas accumulate fresh.
                    // Reasoning is preserved across steps so the user can see
                    // the full thought trail until the run ends.
                    flushIfDue(force: true)
                    liveAssistantText = ""

                case .textDelta(let piece):
                    pendingAssistant += piece
                    flushIfDue()

                case .reasoningDelta(let piece):
                    pendingReasoning += piece
                    flushIfDue()

                case .assistantTurn(let text, _):
                    flushIfDue(force: true)
                    if !text.isEmpty { assembledFinalText = text }
                    // Refresh tool executions snapshot from SDK history so the
                    // tool timeline reflects calls the model just emitted.
                    let allMessages = await sdk.history()
                    let runMessages = Array(allMessages.dropFirst(historyCountBefore))
                    let executions = extractToolExecutions(from: runMessages)
                    let signature = signature(for: executions)
                    if signature != lastToolSignature {
                        latestToolExecutions = executions
                        lastToolSignature = signature
                    }

                case .toolStarted, .toolFinished:
                    flushIfDue(force: true)
                    let allMessages = await sdk.history()
                    let runMessages = Array(allMessages.dropFirst(historyCountBefore))
                    let executions = extractToolExecutions(from: runMessages)
                    let signature = signature(for: executions)
                    if signature != lastToolSignature {
                        latestToolExecutions = executions
                        lastToolSignature = signature
                    }

                case .completed(let result):
                    flushIfDue(force: true)
                    finalResult = result
                }
            }

            let result = finalResult
            let runMessages: [LLMMessage]
            if let result {
                runMessages = Array(result.messages.dropFirst(historyCountBefore))
                latestCompactionSummary = result.compactionSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                let allMessages = await sdk.history()
                runMessages = Array(allMessages.dropFirst(historyCountBefore))
            }
            latestToolExecutions = extractToolExecutions(from: runMessages)
            contextUsage = await sdk.contextUsage()

            let candidate = result?.finalText ?? assembledFinalText
            let text = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
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
               !lastAssistant.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return lastAssistant.text
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

    // MARK: - Todo phases observation

    /// Subscribe to the store's snapshot stream and mirror it into the
    /// `@Published var todoPhases` so SwiftUI views can render it.
    /// Idempotent — replaces any prior observation task.
    private func startTodoObservation() {
        phasesObservation?.cancel()
        let store = todoStore
        phasesObservation = Task { [weak self] in
            for await snapshot in await store.phasesStream() {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.todoPhases = snapshot
                }
            }
        }
    }

    // MARK: - Tool execution extraction (private)

    /// Tools whose calls the live timeline should surface. `read/write/edit/bash`
    /// have always been here; `task` is added so subagent fan-outs render as
    /// first-class rows. `todo_write` and `ask` are intentionally excluded —
    /// they have dedicated UIs (the toolbar progress indicator and the ask
    /// banner) and would be duplicate noise in the timeline.
    private static let trackedTools: Set<String> = ["read", "write", "edit", "bash", "task"]

    private func signature(for executions: [AgentToolExecution]) -> String {
        executions.map { "\($0.id)|\($0.status.rawValue)|\($0.summary)" }.joined(separator: "||")
    }

    private func extractToolExecutions(from messages: [LLMMessage]) -> [AgentToolExecution] {
        let trackedTools = Self.trackedTools

        struct PendingCall {
            let name: String
            let argsJSON: String?
            let order: Int
        }

        var pendingByCallID: [String: PendingCall] = [:]
        var pendingOrder: [String] = []
        var orderCounter = 0

        for message in messages where message.role == .assistant {
            for call in message.toolUses {
                guard trackedTools.contains(call.name) else { continue }
                pendingByCallID[call.id] = PendingCall(name: call.name, argsJSON: call.argumentsJSON, order: orderCounter)
                pendingOrder.append(call.id)
                orderCounter += 1
            }
        }

        var executions: [(order: Int, execution: AgentToolExecution)] = []

        for (index, message) in messages.enumerated() {
            guard message.role == .tool else { continue }

            for (resultIndex, result) in message.toolResults.enumerated() {
                guard trackedTools.contains(result.toolName) else { continue }

                let output = result.content
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                let failed = result.isError || trimmed.hasPrefix("ERROR:")
                let stableID = result.toolUseID.isEmpty ? "\(result.toolName)-\(index)-\(resultIndex)" : result.toolUseID
                let pending = pendingByCallID[result.toolUseID]
                let argsJSON = pending?.argsJSON
                let summary = buildToolSummary(toolName: result.toolName, argumentsJSON: argsJSON)
                let displayOutput = failed ? mapToUserFriendlySandboxMessage(trimmed) + "\n\n" + L10n.tr("agent.raw_error") + ":\n\(trimmed)" : output
                let order = pending?.order ?? (1_000_000 + index * 1000 + resultIndex)

                executions.append((
                    order: order,
                    execution: AgentToolExecution(
                        id: stableID,
                        toolName: result.toolName,
                        status: failed ? .failed : .success,
                        summary: summary,
                        output: displayOutput
                    )
                ))

                pendingByCallID.removeValue(forKey: result.toolUseID)
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
        case "task":
            // Format: "<agentID> × <count>" so the timeline row can extract
            // both pieces. We also pretty-print per-task descriptions into
            // the output panel later.
            let agentID = (obj["agent"] as? String) ?? "subagent"
            let tasks = (obj["tasks"] as? [[String: Any]]) ?? []
            return "\(agentID) × \(tasks.count)"
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
