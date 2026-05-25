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
    @Published var latestCompactionSummary: String?
    @Published var contextUsage: ContextUsage = ContextUsage(usedTokens: 0, totalTokens: 128_000, reservedTokens: 16_384)

    /// Authoritative source for the in-flight assistant turn: an ordered
    /// list of text and tool-call items in the exact emission order the
    /// model produced them. Drives `AgentResponseView` and is the basis
    /// for `persistRunResults`.
    @Published var liveTimeline: [LiveTurnItem] = []

    /// Live-accumulated reasoning / chain-of-thought for the in-flight turn.
    /// Surfaced in a collapsed pane so the user can see the model "thinking"
    /// without it polluting the final answer.
    @Published var liveReasoningText: String = ""

    /// Projection of `liveTimeline` to just the tool executions, in order.
    /// Read by `ChatViewModel.persistRunResults`, the empty-after-tools
    /// fallback below, and todo-summary code paths.
    var latestToolExecutions: [AgentToolExecution] {
        liveTimeline.compactMap {
            if case .tool(let t) = $0 { return t } else { return nil }
        }
    }

    /// Concatenation of all text items in `liveTimeline`. Used only by
    /// the empty-after-tools fallback paths (the live UI iterates the
    /// timeline directly).
    var liveAssistantText: String {
        liveTimeline.reduce(into: "") { acc, item in
            if case .text(_, let content) = item { acc += content }
        }
    }

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
    /// SDK toolUseID of the `task` tool call currently in flight. Subagent
    /// events from `TaskCoordinator` get routed onto this exec's
    /// `subagentLive` list. Set in `appendToolStarted` and cleared on
    /// `applyToolFinished`. There is at most one in-flight `task` call per
    /// turn because the model emits tools sequentially per step.
    private var inFlightTaskToolID: String?

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
        liveTimeline = []
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
        liveTimeline = []
        latestCompactionSummary = nil
        liveReasoningText = ""
        inFlightTaskToolID = nil

        // Forward subagent events to the live timeline so the task-fanout
        // row can render each parallel subagent's inner tool calls as they
        // happen. The coordinator's default observer is sticky for the
        // session — clear it on `defer` so a torn-down SessionAgent
        // doesn't keep receiving events from a later batch.
        let observer = SubagentObserverBridge(target: self)
        await taskCoordinator.setDefaultObserver(observer)

        defer {
            isResponding = false
            // NOTE: don't wipe liveTimeline / liveReasoningText here —
            // the caller (ChatViewModel.persistRunResults) reads
            // them immediately after `sendChat` returns to persist the
            // turn. The next chat run resets both at its top, so leaking
            // them across runs is fine; AgentResponseView only renders
            // live content while isResponding is true anyway.
            AgentManager.shared.applyPendingConfigRebuild(for: id)
            Task { [coordinator = taskCoordinator] in
                await coordinator.setDefaultObserver(nil)
            }
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
                appendAssistantText(pendingAssistant)
                pendingAssistant = ""
            }
            if !pendingReasoning.isEmpty {
                liveReasoningText += pendingReasoning
                pendingReasoning = ""
            }
            lastFlush = now
        }

        @MainActor func appendAssistantText(_ piece: String) {
            // Coalesce into the trailing text block if one already exists;
            // any tool call between two text bursts forces a fresh block,
            // which is what gives us the interleaved `text → tool → text`
            // layout.
            if case .text(let id, let content) = liveTimeline.last {
                liveTimeline[liveTimeline.count - 1] = .text(id: id, content: content + piece)
            } else {
                liveTimeline.append(.text(id: UUID(), content: piece))
            }
        }

        @MainActor func appendToolStarted(_ toolUse: LLMToolUse) {
            guard Self.trackedTools.contains(toolUse.name) else { return }
            let summary = buildToolSummary(toolName: toolUse.name, argumentsJSON: toolUse.argumentsJSON)
            let subagentLive: [SubagentTaskLiveState]
            if toolUse.name == "task" {
                subagentLive = parseInitialSubagentTasks(argumentsJSON: toolUse.argumentsJSON)
            } else {
                subagentLive = []
            }
            let exec = AgentToolExecution(
                id: toolUse.id,
                toolName: toolUse.name,
                status: .running,
                summary: summary,
                output: "",
                argumentsJSON: toolUse.argumentsJSON,
                subagentLive: subagentLive
            )
            liveTimeline.append(.tool(exec))
            if toolUse.name == "task" {
                inFlightTaskToolID = toolUse.id
            }
        }

        @MainActor func applyToolFinished(_ result: LLMToolResult) {
            guard Self.trackedTools.contains(result.toolName) else { return }
            let output = result.content
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let failed = result.isError || trimmed.hasPrefix("ERROR:")
            let displayOutput = failed
                ? mapToUserFriendlySandboxMessage(trimmed) + "\n\n" + L10n.tr("agent.raw_error") + ":\n\(trimmed)"
                : output
            let status: AgentToolExecutionStatus = failed ? .failed : .success

            if let idx = liveTimeline.lastIndex(where: {
                if case .tool(let t) = $0 { return t.id == result.toolUseID } else { return false }
            }),
               case .tool(let existing) = liveTimeline[idx]
            {
                let updated = AgentToolExecution(
                    id: existing.id,
                    toolName: existing.toolName,
                    status: status,
                    summary: existing.summary,
                    output: displayOutput,
                    argumentsJSON: existing.argumentsJSON,
                    subagentLive: existing.subagentLive
                )
                liveTimeline[idx] = .tool(updated)
                if existing.toolName == "task", inFlightTaskToolID == existing.id {
                    inFlightTaskToolID = nil
                }
            } else {
                // Defensive: finished arrived without a matching started.
                let stableID = result.toolUseID.isEmpty ? "\(result.toolName)-\(UUID().uuidString)" : result.toolUseID
                let summary = buildToolSummary(toolName: result.toolName, argumentsJSON: nil)
                liveTimeline.append(.tool(AgentToolExecution(
                    id: stableID,
                    toolName: result.toolName,
                    status: status,
                    summary: summary,
                    output: displayOutput
                )))
            }
        }

        do {
            for try await event in sdk.runStream(prompt: effectivePrompt) {
                try Task.checkCancellation()

                switch event {
                case .stepStarted:
                    // Don't clear the timeline — multi-step turns continue
                    // appending. A tool call between steps naturally forces
                    // a new text block on the next textDelta.
                    flushIfDue(force: true)

                case .textDelta(let piece):
                    pendingAssistant += piece
                    flushIfDue()

                case .reasoningDelta(let piece):
                    pendingReasoning += piece
                    flushIfDue()

                case .assistantTurn(let text, _):
                    flushIfDue(force: true)
                    if !text.isEmpty { assembledFinalText = text }

                case .toolStarted(let toolUse):
                    flushIfDue(force: true)
                    appendToolStarted(toolUse)

                case .toolFinished(let result):
                    flushIfDue(force: true)
                    applyToolFinished(result)

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
            contextUsage = await sdk.contextUsage()

            let candidate = result?.finalText ?? assembledFinalText
            let text = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                if !latestToolExecutions.isEmpty {
                    return L10n.tr("agent.empty_after_tools", latestToolExecutions.count)
                }
                // Some models (extended thinking, redacted thinking) can
                // close a turn with reasoning blocks but no visible text.
                // Surface the reasoning so the user sees *something* rather
                // than a bare "empty content" stub.
                if let reasoning = lastAssistantReasoning(in: runMessages) {
                    return L10n.tr("agent.reasoning_only_response", reasoning)
                }
                return L10n.tr("agent.empty_model_response")
            }
            return text
        } catch AgentLoopError.maxStepsReached {
            let allMessages = await sdk.history()
            let runMessages = Array(allMessages.dropFirst(historyCountBefore))
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
        liveTimeline = []
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
    /// have always been here; `task` surfaces subagent fan-outs as first-class
    /// rows; `todo_write` shows the agent's plan updates inline (matching the
    /// reference Claude Code UX) — the toolbar Progress card stays as the
    /// glanceable summary, the row is the audit trail. `ask` is still
    /// excluded since the ask banner already owns that interaction.
    private static let trackedTools: Set<String> = ["read", "write", "edit", "bash", "task", "todo_write"]

    /// Concatenated reasoning text from the most recent assistant message, if
    /// any. Used as a fallback when the turn ends with reasoning blocks but
    /// no visible answer — better to show the model's thinking than a stub.
    private func lastAssistantReasoning(in messages: [LLMMessage]) -> String? {
        guard let last = messages.last(where: { $0.role == .assistant }) else { return nil }
        let joined = last.content
            .compactMap(\.asReasoning)
            .map(\.text)
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        let trimmed = joined.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

    // MARK: - Subagent fan-out support

    /// Parse `task` tool arguments into the initial per-task live state.
    /// Each entry starts as `running` with zero inner tool runs; the
    /// `SubagentEventObserver` fills in the rest as the batch progresses.
    fileprivate func parseInitialSubagentTasks(argumentsJSON: String?) -> [SubagentTaskLiveState] {
        guard let argumentsJSON,
              let data = argumentsJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        let agentID = (obj["agent"] as? String) ?? "subagent"
        let tasks = (obj["tasks"] as? [[String: Any]]) ?? []
        return tasks.compactMap { dict in
            guard let id = dict["id"] as? String, !id.isEmpty else { return nil }
            let description = (dict["description"] as? String) ?? ""
            return SubagentTaskLiveState(
                id: id,
                agentID: agentID,
                description: description,
                status: .running,
                steps: 0,
                output: "",
                error: nil,
                innerTools: []
            )
        }
    }

    /// Locate the in-flight `task` tool exec in `liveTimeline` and apply
    /// a mutation to it. No-op if there is no matching exec — events that
    /// arrive after `applyToolFinished` simply land on the floor.
    @MainActor
    fileprivate func mutateInFlightTaskExec(_ change: (inout AgentToolExecution) -> Void) {
        guard let id = inFlightTaskToolID else { return }
        guard let idx = liveTimeline.lastIndex(where: {
            if case .tool(let t) = $0 { return t.id == id } else { return false }
        }),
              case .tool(var exec) = liveTimeline[idx]
        else { return }
        change(&exec)
        liveTimeline[idx] = .tool(exec)
    }

    /// Apply one event from the subagent coordinator. Always runs on the
    /// MainActor because it mutates `@Published var liveTimeline`.
    @MainActor
    fileprivate func applySubagentEvent(_ event: SubagentLifecycleEvent) {
        switch event {
        case .started(let taskID, let agentID):
            mutateInFlightTaskExec { exec in
                if let i = exec.subagentLive.firstIndex(where: { $0.id == taskID }) {
                    exec.subagentLive[i].status = .running
                } else {
                    exec.subagentLive.append(SubagentTaskLiveState(
                        id: taskID,
                        agentID: agentID,
                        description: "",
                        status: .running,
                        steps: 0,
                        output: "",
                        error: nil,
                        innerTools: []
                    ))
                }
            }
        case .toolStarted(let taskID, let toolUse):
            mutateInFlightTaskExec { exec in
                guard let i = exec.subagentLive.firstIndex(where: { $0.id == taskID }) else { return }
                let summary = self.buildToolSummary(toolName: toolUse.name, argumentsJSON: toolUse.argumentsJSON)
                exec.subagentLive[i].innerTools.append(SubagentInnerToolState(
                    id: toolUse.id,
                    toolName: toolUse.name,
                    status: .running,
                    summary: summary,
                    output: ""
                ))
            }
        case .toolFinished(let taskID, let result):
            mutateInFlightTaskExec { exec in
                guard let i = exec.subagentLive.firstIndex(where: { $0.id == taskID }) else { return }
                let trimmed = result.content.trimmingCharacters(in: .whitespacesAndNewlines)
                let failed = result.isError || trimmed.hasPrefix("ERROR:")
                let status: AgentToolExecutionStatus = failed ? .failed : .success
                if let j = exec.subagentLive[i].innerTools.firstIndex(where: { $0.id == result.toolUseID }) {
                    exec.subagentLive[i].innerTools[j].status = status
                    exec.subagentLive[i].innerTools[j].output = result.content
                } else {
                    exec.subagentLive[i].innerTools.append(SubagentInnerToolState(
                        id: result.toolUseID.isEmpty ? "\(result.toolName)-\(UUID().uuidString)" : result.toolUseID,
                        toolName: result.toolName,
                        status: status,
                        summary: result.toolName,
                        output: result.content
                    ))
                }
            }
        case .finished(let result):
            mutateInFlightTaskExec { exec in
                guard let i = exec.subagentLive.firstIndex(where: { $0.id == result.id }) else { return }
                exec.subagentLive[i].status = result.success ? .success : .failed
                exec.subagentLive[i].steps = result.steps
                exec.subagentLive[i].output = result.output
                exec.subagentLive[i].error = result.error
            }
        }
    }
}

/// Sendable adapter that forwards `SubagentLifecycleEvent`s onto a
/// `SessionAgent` on the MainActor. The reference is weak so a deleted
/// session doesn't keep the coordinator's batch alive.
private struct SubagentObserverBridge: SubagentEventObserver {
    weak var target: SessionAgent?

    func handle(_ event: SubagentLifecycleEvent) async {
        await MainActor.run { [weak target] in
            target?.applySubagentEvent(event)
        }
    }
}
