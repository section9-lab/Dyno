import AppKit
import Combine
import Foundation
import SwiftData
import SwiftUI

/// Top-level destination for the main content column. The sidebar's first
/// section flips this; chat is the default.
enum ChatRoute {
    case chat
    case kanban
    case autoIntelligence
}

/// In-memory placeholder for a session the user has begun composing but
/// has not yet sent the first message in. Promoted to a real
/// `StoredSession` only on first send. `projectPath == nil` means the
/// session, once committed, will be a project-less ("conversations") row.
struct DraftSession {
    var projectPath: String?
}

/// Owns view-state for the chat surface and the message-write side effects.
/// Reads come straight from SwiftData via `@Query` in views; this class no
/// longer ferries data between disk and UI.
@MainActor
final class ChatViewModel: ObservableObject {
    // MARK: - View state

    @Published var inputText: String = ""
    @Published var showConfigSheet: Bool = false
    @Published var route: ChatRoute = .chat
    @Published var selectedProjectPath: String?
    @Published var selectedSessionID: String?
    /// Set when the user clicks "新对话" (or a project's `+`) but has not
    /// yet sent a message. Cleared by `selectSession` / selecting a project
    /// row / route changes. Committed to a real `StoredSession` on the
    /// first `sendMessage` so empty sessions never pile up.
    @Published var draft: DraftSession?
    @Published var showRenameDialog: Bool = false
    @Published var renamingSessionID: String?
    @Published var renameDraft: String = ""
    @Published var expandedProjectPaths: Set<String> = []

    @Published var sidebarWidth: CGFloat = 260
    @Published var isSidebarCollapsed: Bool = false
    @Published var lastExpandedSidebarWidth: CGFloat = 260
    @Published var dragSidebarStartWidth: CGFloat?

    private let sandboxAccess = SandboxAccessManager.shared

    // MARK: - View state helpers

    var canStartNewChat: Bool {
        selectedProjectPath?.isEmpty == false
    }

    /// True when the chat pane should accept input but render an empty
    /// state instead of an existing session's transcript.
    var isComposingDraft: Bool {
        draft != nil && selectedSessionID == nil
    }

    func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.18)) {
            if isSidebarCollapsed {
                sidebarWidth = max(240, min(lastExpandedSidebarWidth, 520))
                isSidebarCollapsed = false
            } else {
                lastExpandedSidebarWidth = sidebarWidth
                isSidebarCollapsed = true
            }
        }
    }

    func toggleProjectExpansion(_ projectPath: String) {
        if expandedProjectPaths.contains(projectPath) {
            expandedProjectPaths.remove(projectPath)
        } else {
            expandedProjectPaths.insert(projectPath)
        }
    }

    /// Switch the main column to a non-chat destination. Always discards any
    /// in-progress draft because the chat pane is no longer visible.
    func setRoute(_ newRoute: ChatRoute) {
        route = newRoute
        if newRoute != .chat {
            draft = nil
        }
    }

    // MARK: - Project / session selection

    func selectProject(_ projectPath: String, agent: AgentManager) {
        selectedProjectPath = projectPath
        selectedSessionID = nil
        // Preserve an in-progress New Chat draft — just retarget it to the
        // newly-selected project. Without this, picking a project from the
        // input-bar dropdown after tapping "New Chat" would clear the draft
        // and leave the user unable to send.
        if draft != nil {
            draft = DraftSession(projectPath: projectPath)
            expandedProjectPaths.insert(projectPath)
        } else {
            inputText = ""
        }
        route = .chat
        agent.setActiveProjectPath(projectPath)
    }

    func selectSession(projectPath: String, sessionID: String, agent: AgentManager) {
        selectedProjectPath = projectPath.isEmpty ? nil : projectPath
        selectedSessionID = sessionID
        draft = nil
        route = .chat
        agent.setActiveProjectPath(projectPath.isEmpty ? nil : projectPath)
        // Make sure a SessionAgent exists for this session — does not reset
        // an in-flight one if it already exists (parallel sessions).
        _ = agent.sessionAgent(for: sessionID, projectPath: projectPath)
        agent.focusedSessionID = sessionID
    }

    /// Begin composing a new chat without yet creating a `StoredSession`.
    /// `projectPath == nil` means the eventual session will be a
    /// project-less ("conversations") row. The `StoredSession` is only
    /// inserted on the first `sendMessage` (see `commitDraftIfNeeded`).
    func beginDraftSession(projectPath: String?, agent: AgentManager) {
        selectedProjectPath = projectPath
        selectedSessionID = nil
        inputText = ""
        draft = DraftSession(projectPath: projectPath)
        route = .chat
        if let projectPath {
            expandedProjectPaths.insert(projectPath)
        }
        agent.setActiveProjectPath(projectPath)
    }

    // MARK: - Project lifecycle

    /// Open a folder picker, sandbox-authorize the chosen URL, persist a
    /// new `StoredProject` if one doesn't exist for that path, and select it.
    func addProject(modelContext: ModelContext, agent: AgentManager) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = L10n.tr("chat.add_project")
        panel.message = L10n.tr("chat.add_project_panel_message")

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.standardizedFileURL.path

        sandboxAccess.addAuthorizedDirectory(url)

        // Insert StoredProject if not already present.
        let descriptor = FetchDescriptor<StoredProject>(
            predicate: #Predicate { $0.path == path }
        )
        if (try? modelContext.fetch(descriptor))?.first == nil {
            modelContext.insert(StoredProject(path: path))
        }

        expandedProjectPaths.insert(path)
        if selectedProjectPath == nil {
            selectedProjectPath = path
            selectedSessionID = nil
            agent.setActiveProjectPath(path)
        }
    }

    /// Remove a project, all its sessions, and all its Kanban tasks.
    func removeProject(path: String, modelContext: ModelContext, agent: AgentManager) {
        // Delete sessions (cascades to messages/toolRuns/summaries via inverse).
        let sessionsDescriptor = FetchDescriptor<StoredSession>(
            predicate: #Predicate { $0.projectPath == path }
        )
        for session in (try? modelContext.fetch(sessionsDescriptor)) ?? [] {
            agent.discardSessionAgent(for: session.id)
            modelContext.delete(session)
        }

        // Delete Kanban tasks.
        let tasksDescriptor = FetchDescriptor<StoredKanbanTask>(
            predicate: #Predicate { $0.projectPath == path }
        )
        for task in (try? modelContext.fetch(tasksDescriptor)) ?? [] {
            modelContext.delete(task)
        }

        // Delete project entity.
        let projectDescriptor = FetchDescriptor<StoredProject>(
            predicate: #Predicate { $0.path == path }
        )
        for project in (try? modelContext.fetch(projectDescriptor)) ?? [] {
            modelContext.delete(project)
        }

        expandedProjectPaths.remove(path)
        if selectedProjectPath == path {
            selectedProjectPath = nil
            selectedSessionID = nil
            agent.setActiveProjectPath(nil)
        }
    }

    /// Commit the in-progress `draft` into a real `StoredSession` and
    /// return it. Caller is responsible for invoking only when there is
    /// actually a draft. After this returns, `selectedSessionID` is set
    /// and `draft` is cleared.
    @discardableResult
    func commitDraftIfNeeded(modelContext: ModelContext, agent: AgentManager) -> StoredSession? {
        guard let draft else { return nil }

        let sessionID = UUID().uuidString
        let projectPath = draft.projectPath ?? ""
        let session = StoredSession(
            id: sessionID,
            projectPath: projectPath,
            title: L10n.tr("chat.new_session"),
            startedAt: Date()
        )
        modelContext.insert(session)

        selectedProjectPath = projectPath.isEmpty ? nil : projectPath
        selectedSessionID = sessionID
        self.draft = nil
        if !projectPath.isEmpty {
            expandedProjectPaths.insert(projectPath)
        }
        agent.setActiveProjectPath(projectPath.isEmpty ? nil : projectPath)
        agent.resetSessionAgent(for: sessionID, projectPath: projectPath)
        agent.focusedSessionID = sessionID
        return session
    }

    // MARK: - Session rename / delete

    func requestRename(_ session: StoredSession) {
        renamingSessionID = session.id
        renameDraft = session.title
        showRenameDialog = true
    }

    /// Apply the pending rename. Updates `StoredSession.title` and the
    /// first user message's content (the existing UI contract).
    @discardableResult
    func applyRename(modelContext: ModelContext) -> Bool {
        guard let sessionID = renamingSessionID else { return false }
        let normalized = normalizedTitle(from: renameDraft)
        guard normalized != "(empty)" else { return false }

        let descriptor = FetchDescriptor<StoredSession>(
            predicate: #Predicate { $0.id == sessionID }
        )
        guard let session = (try? modelContext.fetch(descriptor))?.first else {
            return false
        }
        session.title = normalized
        if let firstUser = session.messages
            .filter({ $0.role == "user" })
            .sorted(by: { $0.timestamp < $1.timestamp })
            .first {
            firstUser.content = normalized
        }

        renamingSessionID = nil
        return true
    }

    func deleteSession(_ session: StoredSession, modelContext: ModelContext) {
        let id = session.id
        AgentManager.shared.discardSessionAgent(for: id)
        modelContext.delete(session)

        if selectedSessionID == id {
            selectedSessionID = nil
        }
    }

    // MARK: - Message send / compact

    /// Send the user's input on the given session, or commit the current
    /// draft and send on the freshly-created session. Empties `inputText`
    /// on success.
    func sendMessage(modelContext: ModelContext, agent: AgentManager, session: StoredSession?) {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Resolve target session: either the one the caller passed (a
        // committed StoredSession) or commit the current draft.
        let targetSession: StoredSession
        if let session {
            targetSession = session
        } else if let committed = commitDraftIfNeeded(modelContext: modelContext, agent: agent) {
            targetSession = committed
        } else {
            return
        }

        if trimmed.lowercased().hasPrefix("/compact") {
            handleCompactCommand(input: trimmed, modelContext: modelContext, agent: agent, session: targetSession)
            return
        }

        let prelude = buildContinuationPrelude(from: targetSession)

        // Insert the user message + update title if this is the first.
        let userMsg = StoredMessage(timestamp: Date(), role: "user", content: trimmed, session: targetSession)
        modelContext.insert(userMsg)
        if targetSession.title == L10n.tr("chat.new_session") || targetSession.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            targetSession.title = normalizedTitle(from: trimmed)
        }
        inputText = ""

        let sessionAgent = agent.sessionAgent(for: targetSession.id, projectPath: targetSession.projectPath)

        let task = Task { [weak self] in
            do {
                let response = try await sessionAgent.sendChat(prompt: trimmed, contextPrelude: prelude)
                await MainActor.run {
                    self?.persistRunResults(
                        responseText: response,
                        sessionAgent: sessionAgent,
                        session: targetSession,
                        modelContext: modelContext
                    )
                }
            } catch {
                await MainActor.run {
                    self?.persistRunResults(
                        responseText: L10n.tr("chat.error_message", error.localizedDescription),
                        sessionAgent: sessionAgent,
                        session: targetSession,
                        modelContext: modelContext
                    )
                }
            }
        }
        sessionAgent.registerCurrentTask(task)
    }

    private func handleCompactCommand(
        input: String,
        modelContext: ModelContext,
        agent: AgentManager,
        session: StoredSession
    ) {
        let userMsg = StoredMessage(timestamp: Date(), role: "user", content: input, session: session)
        modelContext.insert(userMsg)
        inputText = ""

        let sessionAgent = agent.sessionAgent(for: session.id, projectPath: session.projectPath)
        let instructions = compactInstructions(from: input)

        let task = Task { [weak self] in
            do {
                let summary = try await sessionAgent.compact(customInstructions: instructions)
                let responseText = if let summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    L10n.tr("chat.compaction_completed")
                } else {
                    L10n.tr("chat.compaction_not_enough_content")
                }
                await MainActor.run {
                    self?.persistRunResults(
                        responseText: responseText,
                        sessionAgent: sessionAgent,
                        session: session,
                        modelContext: modelContext
                    )
                }
            } catch {
                await MainActor.run {
                    self?.persistRunResults(
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
                status: execution.status.rawValue,
                summary: execution.summary,
                output: execution.output,
                session: session
            )
            modelContext.insert(run)
            nextTimestamp = nextTimestamp.addingTimeInterval(0.001)
        }

        let trimmedReasoning = sessionAgent.liveReasoningText.trimmingCharacters(in: .whitespacesAndNewlines)
        let assistantMsg = StoredMessage(
            timestamp: nextTimestamp,
            role: "assistant",
            content: responseText,
            reasoning: trimmedReasoning.isEmpty ? nil : sessionAgent.liveReasoningText,
            session: session
        )
        modelContext.insert(assistantMsg)

        if let summary = sessionAgent.latestCompactionSummary,
           !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           session.compactionSummaries.last?.content.trimmingCharacters(in: .whitespacesAndNewlines) != summary
        {
            let s = StoredCompactionSummary(timestamp: Date(), content: summary, session: session)
            modelContext.insert(s)
        }
    }

    private func compactInstructions(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "/compact"
        guard trimmed.lowercased().hasPrefix(prefix) else { return nil }
        let remainder = trimmed.dropFirst(prefix.count)
        let instructions = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        return instructions.isEmpty ? nil : instructions
    }

    /// Build a "continue from history" prelude for the SDK from the
    /// session's last 8 messages + most recent compaction summary. Compensates
    /// for the SDK not persisting its own conversation history across runs.
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

    private func normalizedTitle(from raw: String) -> String {
        let singleLine = raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return singleLine.isEmpty ? "(empty)" : singleLine
    }
}
