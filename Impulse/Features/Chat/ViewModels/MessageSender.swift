import Foundation
import SwiftData

/// Sends user messages on a given `StoredSession` via the `SessionAgent`,
/// persists the resulting tool runs, assistant message, and (optional)
/// compaction summary back into SwiftData.
///
/// Pulled out of `ChatViewModel` so view state (`inputText`, sidebar, etc.)
/// stops mingling with the chat write path. The sender is stateless — every
/// `send` is one self-contained transaction.
///
/// Threading: `@MainActor` because it touches `@Model` instances and
/// schedules main-actor `Task`s for SDK callbacks.
@MainActor
struct MessageSender {

    /// Send `prompt` on `session`. Builds the SDK continuation prelude from
    /// the session's persisted history, dispatches asynchronously on the
    /// session's `SessionAgent`, and writes the result back when ready.
    ///
    /// Recognises `/compact` as a special command — see `compact(...)`.
    func send(
        prompt rawPrompt: String,
        in session: StoredSession,
        modelContext: ModelContext,
        agent: AgentManager
    ) {
        let trimmed = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if trimmed.lowercased().hasPrefix("/compact") {
            compact(input: trimmed, in: session, modelContext: modelContext, agent: agent)
            return
        }

        let prelude = buildContinuationPrelude(from: session)
        let userMsg = StoredMessage(timestamp: Date(), role: .user, content: trimmed, session: session)
        modelContext.insert(userMsg)

        // Set the session title to the first prompt if the session is fresh.
        let isFresh = session.title == L10n.tr("chat.new_session")
            || session.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isFresh {
            session.title = Self.shortTitle(from: trimmed)
        }

        let sessionAgent = agent.sessionAgent(for: session.id, projectPath: session.projectPath)

        let task = Task {
            do {
                let response = try await sessionAgent.sendChat(prompt: trimmed, contextPrelude: prelude)
                await MainActor.run {
                    persistRunResults(
                        responseText: response,
                        sessionAgent: sessionAgent,
                        session: session,
                        modelContext: modelContext
                    )
                }
            } catch {
                await MainActor.run {
                    persistRunResults(
                        responseText: L10n.tr("chat.error_message", error.localizedDescription),
                        sessionAgent: sessionAgent,
                        session: session,
                        modelContext: modelContext
                    )
                }
            }
        }
        sessionAgent.registerCurrentTask(task)
    }

    // MARK: - Private

    /// Handles `/compact ...` — asks the SDK to roll up the current session
    /// into a summary; the user's literal `/compact` prompt itself is logged
    /// as a normal user message so the transcript stays linear.
    private func compact(
        input: String,
        in session: StoredSession,
        modelContext: ModelContext,
        agent: AgentManager
    ) {
        let userMsg = StoredMessage(timestamp: Date(), role: .user, content: input, session: session)
        modelContext.insert(userMsg)

        let sessionAgent = agent.sessionAgent(for: session.id, projectPath: session.projectPath)
        let instructions = Self.compactInstructions(from: input)

        let task = Task {
            do {
                let summary = try await sessionAgent.compact(customInstructions: instructions)
                let responseText: String = if let summary,
                                              !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    L10n.tr("chat.compaction_completed")
                } else {
                    L10n.tr("chat.compaction_not_enough_content")
                }
                await MainActor.run {
                    persistRunResults(
                        responseText: responseText,
                        sessionAgent: sessionAgent,
                        session: session,
                        modelContext: modelContext
                    )
                }
            } catch {
                await MainActor.run {
                    persistRunResults(
                        responseText: L10n.tr("chat.compaction_failed", error.localizedDescription),
                        sessionAgent: sessionAgent,
                        session: session,
                        modelContext: modelContext
                    )
                }
            }
        }
        sessionAgent.registerCurrentTask(task)
    }

    /// Write tool runs + assistant message + (optional) compaction summary
    /// captured by the SessionAgent during one chat run.
    private func persistRunResults(
        responseText: String,
        sessionAgent: SessionAgent,
        session: StoredSession,
        modelContext: ModelContext
    ) {
        var nextTimestamp = Date()
        for execution in sessionAgent.latestToolExecutions {
            let run = StoredToolRun(
                id: execution.id,
                timestamp: nextTimestamp,
                toolName: execution.toolName,
                status: ToolRunStatus(executionStatus: execution.status),
                summary: execution.summary,
                output: execution.output,
                session: session
            )
            modelContext.insert(run)
            nextTimestamp = nextTimestamp.addingTimeInterval(0.001)
        }

        let assistantMsg = StoredMessage(
            timestamp: nextTimestamp,
            role: .assistant,
            content: responseText,
            session: session
        )
        modelContext.insert(assistantMsg)

        if let summary = sessionAgent.latestCompactionSummary,
           !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           session.compactionSummaries.last?.content
            .trimmingCharacters(in: .whitespacesAndNewlines) != summary
        {
            let s = StoredCompactionSummary(timestamp: Date(), content: summary, session: session)
            modelContext.insert(s)
        }
    }

    /// Build a "continue from history" prelude for the SDK from the
    /// session's last 8 messages + most recent compaction summary.
    /// Compensates for the SDK not persisting its own conversation history
    /// across runs.
    private func buildContinuationPrelude(from session: StoredSession) -> String? {
        let messages = session.messages.sorted { $0.timestamp < $1.timestamp }
        let transcriptLines = messages.suffix(8).compactMap { m -> String? in
            let role = m.isUser ? "用户" : "助手"
            let content = m.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return content.isEmpty ? nil : "[\(role)] \(content)"
        }
        let summary = session.compactionSummaries
            .sorted { $0.timestamp < $1.timestamp }
            .last?
            .content
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !transcriptLines.isEmpty || !(summary ?? "").isEmpty else { return nil }

        var sections: [String] = [
            "你正在延续同一个会话（应用可能已重启）。请严格基于下面的历史继续，不要重置上下文。"
        ]
        if let summary, !summary.isEmpty {
            sections.append("[历史压缩摘要]\n\(summary)")
        }
        if !transcriptLines.isEmpty {
            sections.append("[最近对话]\n\(transcriptLines.joined(separator: "\n"))")
        }
        return sections.joined(separator: "\n\n")
    }

    private static func compactInstructions(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "/compact"
        guard trimmed.lowercased().hasPrefix(prefix) else { return nil }
        let remainder = trimmed.dropFirst(prefix.count)
        let instructions = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        return instructions.isEmpty ? nil : instructions
    }

    private static func shortTitle(from text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "(empty)" : cleaned
    }
}
