import AppKit
import Combine
import Foundation
import SwiftData
import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var showConfigSheet: Bool = false
    @Published var showKanbanPanel: Bool = false
    @Published var selectedProjectPath: String?
    @Published var selectedSessionID: String?
    @Published var showRenameDialog: Bool = false
    @Published var renamingSessionID: String?
    @Published var renameDraft: String = ""
    @Published var showAddProjectPicker: Bool = false
    @Published var isImportingSessionFiles: Bool = false
    @Published var expandedProjectPaths: Set<String> = []

    @Published var sidebarWidth: CGFloat = 260
    @Published var isSidebarCollapsed: Bool = false
    @Published var lastExpandedSidebarWidth: CGFloat = 260
    @Published var dragSidebarStartWidth: CGFloat?

    @Published private(set) var persistedProjects: [ProjectSnapshot] = []

    private let historyService = ChatHistoryService()
    private let sandboxAccess = SandboxAccessManager.shared

    // Debounce machinery for `persistProjects`.
    private var persistDebounceTask: Task<Void, Never>?
    private var pendingPersistItems: [Item]?
    private var pendingPersistAgent: AgentManager?

    // Caches for derived view data. Cleared whenever inputs change.
    private var cachedDisplayedRows: [ChatRow]?
    private var cachedDisplayedRowsKey: DisplayedRowsCacheKey?
    private var decodedToolExecutionCache: [Int: PersistedToolExecution] = [:]

    // Cache for the global "flatten all items" projection.
    private var cachedFlattenedItems: [Item]?
    private var cachedFlattenKey: FlattenCacheKey?

    func loadProjects(agent: AgentManager) {
        persistedProjects = agent.loadPersistedProjects()
        expandedProjectPaths.formUnion(persistedProjects.map(\.path))
        ensureProjectSelection(agent: agent)
    }

    /// Flatten all chat rows across all sessions into a single chronologically
    /// sorted `[Item]` list. This preserves the legacy "global items" abstraction
    /// the rest of the codebase still uses, while sourcing data from the new
    /// relational SwiftData model.
    ///
    /// SwiftData re-evaluates the @Query frequently; we cache by a cheap key
    /// (session count + sum of children counts) so re-renders don't reproject.
    func flattenAllItems(from sessions: [StoredSession]) -> [Item] {
        let key = FlattenCacheKey(
            sessionCount: sessions.count,
            messageCount: sessions.reduce(0) { $0 + $1.messages.count },
            toolRunCount: sessions.reduce(0) { $0 + $1.toolRuns.count },
            summaryCount: sessions.reduce(0) { $0 + $1.compactionSummaries.count }
        )
        if cachedFlattenKey == key, let cached = cachedFlattenedItems {
            return cached
        }

        var items: [Item] = []
        items.reserveCapacity(key.messageCount + key.toolRunCount + key.summaryCount)
        for session in sessions {
            for m in session.messages {
                items.append(m.toItem())
            }
            for t in session.toolRuns {
                if let item = t.toItem() {
                    items.append(item)
                }
            }
            for s in session.compactionSummaries {
                items.append(s.toItem())
            }
        }
        items.sort { $0.timestamp < $1.timestamp }

        cachedFlattenKey = key
        cachedFlattenedItems = items
        return items
    }

    func makeProjects(from items: [Item]) -> [ChatProject] {
        historyService.buildProjects(from: items, persistedProjects: persistedProjects)
    }

    func makeSelectedProject(from items: [Item]) -> ChatProject? {
        historyService.selectedProject(selectedPath: selectedProjectPath, projects: makeProjects(from: items))
    }

    func makeSelectedSession(from items: [Item]) -> ChatSession? {
        historyService.selectedSession(
            selectedProjectPath: selectedProjectPath,
            selectedSessionID: selectedSessionID,
            projects: makeProjects(from: items)
        )
    }

    func makeDisplayedItems(from items: [Item]) -> [Item] {
        historyService.displayedItems(
            selectedProjectPath: selectedProjectPath,
            selectedSessionID: selectedSessionID,
            projects: makeProjects(from: items)
        )
    }

    /// Build the row list (interleaving messages and tool-execution groups)
    /// once per (session, item-count, last-timestamp) tuple. SwiftUI re-evaluates
    /// container bodies frequently — this avoids repeating the O(N) walk
    /// + O(K) JSON decodes on every re-render.
    func makeDisplayedRows(from items: [Item]) -> [ChatRow] {
        let displayed = makeDisplayedItems(from: items)
        let key = DisplayedRowsCacheKey(
            sessionID: selectedSessionID,
            count: displayed.count,
            lastTimestamp: displayed.last?.timestamp,
            firstItemID: displayed.first?.id.hashValue
        )
        if cachedDisplayedRowsKey == key, let cached = cachedDisplayedRows {
            return cached
        }

        var rows: [ChatRow] = []
        var pendingTools: [PersistedToolExecution] = []
        var firstGroupItemID: String?

        func flushTools() {
            guard !pendingTools.isEmpty, let groupID = firstGroupItemID else {
                pendingTools = []
                firstGroupItemID = nil
                return
            }
            rows.append(.toolGroup(ToolExecutionGroup(id: "group-\(groupID)", executions: pendingTools)))
            pendingTools = []
            firstGroupItemID = nil
        }

        for item in displayed {
            if item.kindEnum == .toolExecution,
               let payload = cachedDecodedToolExecution(for: item)
            {
                if firstGroupItemID == nil { firstGroupItemID = "\(item.id.hashValue)" }
                pendingTools.append(payload)
            } else {
                flushTools()
                rows.append(.message(item))
            }
        }
        flushTools()

        cachedDisplayedRowsKey = key
        cachedDisplayedRows = rows
        return rows
    }

    /// Per-item decoded tool-execution cache. Keyed on the item's persistent id;
    /// because Items are append-only and content immutable for tool_execution,
    /// the cached value never goes stale for an existing id.
    private func cachedDecodedToolExecution(for item: Item) -> PersistedToolExecution? {
        let key = item.id.hashValue
        if let hit = decodedToolExecutionCache[key] {
            return hit
        }
        guard let data = item.content.data(using: .utf8) else { return nil }
        do {
            let payload = try JSONDecoder().decode(PersistedToolExecution.self, from: data)
            decodedToolExecutionCache[key] = payload
            return payload
        } catch {
            AppLog.persistence.error("Failed to decode tool_execution Item: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func makeKanbanTasks(from items: [Item]) -> [KanbanTaskSnapshot] {
        guard let projectPath = selectedProjectPath else { return [] }
        return historyService.kanbanTasks(for: projectPath, persistedProjects: persistedProjects)
            .sorted { lhs, rhs in
                if lhs.status != rhs.status {
                    return lhs.status.rawValue < rhs.status.rawValue
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    var canStartNewChat: Bool {
        selectedProjectPath?.isEmpty == false
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

    func selectProject(_ projectPath: String, agent: AgentManager) {
        selectedProjectPath = projectPath
        selectedSessionID = nil
        inputText = ""
        updateAgentProjectDirectory(agent: agent)
    }

    func selectSession(projectPath: String, sessionID: String, agent: AgentManager) {
        selectedProjectPath = projectPath
        selectedSessionID = sessionID
        updateAgentProjectDirectory(agent: agent)
        // Make sure a SessionAgent exists for this session — does not reset
        // an in-flight one if it already exists (parallel sessions).
        _ = agent.sessionAgent(for: sessionID, projectPath: projectPath)
        agent.focusedSessionID = sessionID
    }

    func toggleKanbanPanel() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showKanbanPanel.toggle()
        }
    }

    func startNewChat(items: [Item], agent: AgentManager) -> Bool {
        guard let projectPath = selectedProjectPath else { return false }
        guard let result = historyService.createSession(in: projectPath, persistedProjects: persistedProjects) else {
            return false
        }

        persistedProjects = result.projects
        selectedSessionID = result.sessionID
        inputText = ""
        expandedProjectPaths.insert(projectPath)
        updateAgentProjectDirectory(agent: agent)
        // Fresh SDK for the new session.
        agent.resetSessionAgent(for: result.sessionID, projectPath: projectPath)
        agent.focusedSessionID = result.sessionID
        return true
    }

    func addProject(agent: AgentManager) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = L10n.tr("chat.add_project")
        panel.message = L10n.tr("chat.add_project_panel_message")

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let normalizedPath = url.standardizedFileURL.path

        sandboxAccess.addAuthorizedDirectory(url)
        persistedProjects = historyService.addProject(path: normalizedPath, existingProjects: persistedProjects)
        expandedProjectPaths.insert(normalizedPath)
        if selectedProjectPath == nil {
            selectedProjectPath = normalizedPath
            selectedSessionID = nil
            updateAgentProjectDirectory(agent: agent)
        }
    }

    func removeProject(_ project: ChatProject, items: [Item], modelContext: ModelContext, agent: AgentManager) {
        persistedProjects = historyService.removeProject(
            path: project.path,
            persistedProjects: persistedProjects,
            modelContext: modelContext
        )
        expandedProjectPaths.remove(project.path)

        if selectedProjectPath == project.path {
            selectedProjectPath = nil
            selectedSessionID = nil
            ensureProjectSelection(agent: agent)
        }
    }

    func loadConversationsFromSessionFilesIfNeeded(
        items: [Item],
        modelContext: ModelContext,
        agent: AgentManager
    ) {
        loadProjects(agent: agent)
        guard items.isEmpty else { return }
        guard !persistedProjects.isEmpty else { return }

        isImportingSessionFiles = true
        defer { isImportingSessionFiles = false }
        historyService.restoreSnapshots(persistedProjects, into: modelContext)
    }

    func persistProjects(items: [Item], agent: AgentManager) {
        // Coalesce rapid bursts of persistProjects calls (multiple parallel
        // sessions returning around the same time can each trigger this via
        // their `persist()` callback). We schedule one disk write ~200ms
        // after the last call instead of one per insert.
        pendingPersistItems = items
        pendingPersistAgent = agent
        persistDebounceTask?.cancel()
        persistDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled, let self else { return }
            self.flushPendingPersist()
        }
    }

    /// Forces an immediate persist write, bypassing the debounce. Useful on
    /// shutdown or before navigating to settings.
    func flushPendingPersist() {
        guard let items = pendingPersistItems, let agent = pendingPersistAgent else { return }
        var updatedProjects = persistedProjects
        for project in makeProjects(from: items) {
            for session in project.sessions {
                historyService.updateSessionSnapshot(
                    projectPath: project.path,
                    sessionID: session.id,
                    items: items,
                    persistedProjects: &updatedProjects
                )
            }
        }
        persistedProjects = updatedProjects
        agent.persistProjects(updatedProjects)
        pendingPersistItems = nil
        pendingPersistAgent = nil
        persistDebounceTask = nil
    }

    func createKanbanTask(
        title rawTitle: String,
        priority: KanbanTaskPriority,
        status: KanbanTaskStatus
    ) {
        guard let projectPath = selectedProjectPath else { return }
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        let linkedSessionIDs = selectedSessionID.map { [$0] } ?? []
        let task = KanbanTaskSnapshot(
            id: UUID().uuidString,
            projectPath: projectPath,
            title: title,
            status: status,
            priority: priority,
            primarySessionID: selectedSessionID,
            linkedSessionIDs: linkedSessionIDs,
            assigneeName: "AI",
            notes: "",
            createdAt: Date(),
            updatedAt: Date()
        )

        historyService.upsertKanbanTask(task, persistedProjects: &persistedProjects)
    }

    func moveKanbanTask(
        _ task: KanbanTaskSnapshot,
        to status: KanbanTaskStatus
    ) {
        let updated = KanbanTaskSnapshot(
            id: task.id,
            projectPath: task.projectPath,
            title: task.title,
            status: status,
            priority: task.priority,
            primarySessionID: task.primarySessionID,
            linkedSessionIDs: task.linkedSessionIDs,
            assigneeName: task.assigneeName,
            notes: task.notes,
            createdAt: task.createdAt,
            updatedAt: Date()
        )
        historyService.upsertKanbanTask(updated, persistedProjects: &persistedProjects)
    }

    func linkSelectedSessionToKanbanTask(_ task: KanbanTaskSnapshot) {
        guard let selectedSessionID else { return }
        var linked = task.linkedSessionIDs
        if !linked.contains(selectedSessionID) {
            linked.append(selectedSessionID)
        }
        let updated = KanbanTaskSnapshot(
            id: task.id,
            projectPath: task.projectPath,
            title: task.title,
            status: task.status,
            priority: task.priority,
            primarySessionID: task.primarySessionID ?? selectedSessionID,
            linkedSessionIDs: linked,
            assigneeName: task.assigneeName,
            notes: task.notes,
            createdAt: task.createdAt,
            updatedAt: Date()
        )
        historyService.upsertKanbanTask(updated, persistedProjects: &persistedProjects)
    }

    func deleteKanbanTask(_ task: KanbanTaskSnapshot) {
        historyService.deleteKanbanTask(id: task.id, projectPath: task.projectPath, persistedProjects: &persistedProjects)
    }

    func requestRename(_ session: ChatSession) {
        renamingSessionID = session.id
        renameDraft = session.title
        showRenameDialog = true
    }

    @discardableResult
    func applyRename(items: [Item], modelContext: ModelContext) -> Bool {
        guard let projectPath = selectedProjectPath,
              let sessionID = renamingSessionID
        else {
            return false
        }

        let didRename = historyService.renameSession(
            projectPath: projectPath,
            sessionID: sessionID,
            newTitle: renameDraft,
            items: items,
            persistedProjects: &persistedProjects,
            modelContext: modelContext
        )
        guard didRename else { return false }

        renamingSessionID = nil
        invalidateDisplayedRowsCache()
        return true
    }

    func deleteSession(_ session: ChatSession, modelContext: ModelContext) {
        historyService.deleteSession(
            projectPath: session.projectPath,
            sessionID: session.id,
            persistedProjects: &persistedProjects,
            modelContext: modelContext
        )

        AgentManager.shared.discardSessionAgent(for: session.id)
        invalidateDisplayedRowsCache()

        if selectedSessionID == session.id {
            selectedSessionID = nil
        }
    }

    /// Invalidate row + decode caches. Call after mutating writes that aren't
    /// captured by the cache key (e.g. deleting items from a session).
    private func invalidateDisplayedRowsCache() {
        cachedDisplayedRows = nil
        cachedDisplayedRowsKey = nil
        cachedFlattenedItems = nil
        cachedFlattenKey = nil
        // Don't bulk-clear decodedToolExecutionCache — items keep their stable
        // persistent ids, so cached entries for surviving items remain valid.
        // Stale entries for deleted items are tiny and will age out when
        // the dictionary is recreated on session switch (cheap).
    }

    // MARK: - SwiftData write helpers
    //
    // These find-or-create a `StoredSession` for the given (projectPath,
    // sessionID) and insert the appropriate child entity (StoredMessage,
    // StoredToolRun, or StoredCompactionSummary). They replace the old
    // single-table `Item` insert pattern.

    private func ensureStoredSession(
        sessionID: String,
        projectPath: String,
        startedAt: Date,
        title: String,
        modelContext: ModelContext
    ) -> StoredSession {
        let predicate = #Predicate<StoredSession> { $0.id == sessionID }
        let descriptor = FetchDescriptor<StoredSession>(predicate: predicate)
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            return existing
        }
        let session = StoredSession(
            id: sessionID,
            projectPath: projectPath,
            title: title,
            startedAt: startedAt
        )
        modelContext.insert(session)
        return session
    }

    @discardableResult
    private func insertUserMessage(
        timestamp: Date = Date(),
        content: String,
        sessionID: String,
        projectPath: String,
        modelContext: ModelContext
    ) -> StoredMessage {
        let session = ensureStoredSession(
            sessionID: sessionID,
            projectPath: projectPath,
            startedAt: timestamp,
            title: shortTitle(from: content),
            modelContext: modelContext
        )
        let message = StoredMessage(timestamp: timestamp, role: "user", content: content, session: session)
        modelContext.insert(message)
        invalidateDisplayedRowsCache()
        return message
    }

    @discardableResult
    private func insertAssistantMessage(
        timestamp: Date = Date(),
        content: String,
        sessionID: String,
        projectPath: String,
        modelContext: ModelContext
    ) -> StoredMessage {
        let session = ensureStoredSession(
            sessionID: sessionID,
            projectPath: projectPath,
            startedAt: timestamp,
            title: "(empty)",
            modelContext: modelContext
        )
        let message = StoredMessage(timestamp: timestamp, role: "assistant", content: content, session: session)
        modelContext.insert(message)
        invalidateDisplayedRowsCache()
        return message
    }

    @discardableResult
    private func insertToolRun(
        execution: AgentToolExecution,
        timestamp: Date,
        sessionID: String,
        projectPath: String,
        modelContext: ModelContext
    ) -> StoredToolRun {
        let session = ensureStoredSession(
            sessionID: sessionID,
            projectPath: projectPath,
            startedAt: timestamp,
            title: "(empty)",
            modelContext: modelContext
        )
        let run = StoredToolRun(
            id: execution.id,
            timestamp: timestamp,
            toolName: execution.toolName,
            status: execution.status.rawValue,
            summary: execution.summary,
            output: execution.output,
            session: session
        )
        modelContext.insert(run)
        invalidateDisplayedRowsCache()
        return run
    }

    @discardableResult
    private func insertCompactionSummary(
        timestamp: Date = Date(),
        content: String,
        sessionID: String,
        projectPath: String,
        modelContext: ModelContext
    ) -> StoredCompactionSummary {
        let session = ensureStoredSession(
            sessionID: sessionID,
            projectPath: projectPath,
            startedAt: timestamp,
            title: "(empty)",
            modelContext: modelContext
        )
        let summary = StoredCompactionSummary(timestamp: timestamp, content: content, session: session)
        modelContext.insert(summary)
        invalidateDisplayedRowsCache()
        return summary
    }

    private func shortTitle(from text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "(empty)" : cleaned
    }

    func sendMessage(
        modelContext: ModelContext,
        agent: AgentManager,
        session: ChatSession?,
        conversationItems: [Item],
        persist: @escaping () -> Void
    ) {
        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        guard let projectPath = selectedProjectPath,
              let session
        else {
            return
        }

        if trimmedText.lowercased().hasPrefix("/compact") {
            handleCompactCommand(
                input: trimmedText,
                projectPath: projectPath,
                sessionID: session.id,
                modelContext: modelContext,
                agent: agent,
                conversationItems: conversationItems,
                persist: persist
            )
            return
        }

        let contextPrelude = buildContinuationPrelude(from: conversationItems)
        let userMessage = insertUserMessage(
            content: trimmedText,
            sessionID: session.id,
            projectPath: projectPath,
            modelContext: modelContext
        )
        let userMessageItem = userMessage.toItem()
        inputText = ""

        // Dispatch on this session's own SessionAgent — other sessions can run
        // their own chats in parallel without sharing state with this one.
        let sessionAgent = agent.sessionAgent(for: session.id, projectPath: projectPath)
        persist()

        let task = Task {
            do {
                let response = try await sessionAgent.sendChat(prompt: trimmedText, contextPrelude: contextPrelude)
                let responseTimestamp = appendSessionToolExecutionItems(
                    modelContext: modelContext,
                    sessionAgent: sessionAgent,
                    projectPath: projectPath,
                    sessionID: session.id,
                    startingAt: Date()
                )
                let aiResponse = insertAssistantMessage(
                    timestamp: responseTimestamp,
                    content: response,
                    sessionID: session.id,
                    projectPath: projectPath,
                    modelContext: modelContext
                )
                let aiResponseItem = aiResponse.toItem()
                appendSessionCompactionSummaryItemIfNeeded(
                    modelContext: modelContext,
                    sessionAgent: sessionAgent,
                    projectPath: projectPath,
                    sessionID: session.id,
                    conversationItems: conversationItems + [userMessageItem, aiResponseItem]
                )
                persist()
            } catch {
                let responseTimestamp = appendSessionToolExecutionItems(
                    modelContext: modelContext,
                    sessionAgent: sessionAgent,
                    projectPath: projectPath,
                    sessionID: session.id,
                    startingAt: Date()
                )
                _ = insertAssistantMessage(
                    timestamp: responseTimestamp,
                    content: L10n.tr("chat.error_message", error.localizedDescription),
                    sessionID: session.id,
                    projectPath: projectPath,
                    modelContext: modelContext
                )
                persist()
            }
        }
        sessionAgent.registerCurrentTask(task)
    }

    private func handleCompactCommand(
        input: String,
        projectPath: String,
        sessionID: String,
        modelContext: ModelContext,
        agent: AgentManager,
        conversationItems: [Item],
        persist: @escaping () -> Void
    ) {
        let userMessage = insertUserMessage(
            content: input,
            sessionID: sessionID,
            projectPath: projectPath,
            modelContext: modelContext
        )
        let userMessageItem = userMessage.toItem()
        inputText = ""
        let sessionAgent = agent.sessionAgent(for: sessionID, projectPath: projectPath)
        persist()

        let instructions = compactInstructions(from: input)

        let task = Task {
            do {
                let summary = try await sessionAgent.compact(customInstructions: instructions)
                let responseText = if let summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    L10n.tr("chat.compaction_completed")
                } else {
                    L10n.tr("chat.compaction_not_enough_content")
                }

                let responseTimestamp = appendSessionToolExecutionItems(
                    modelContext: modelContext,
                    sessionAgent: sessionAgent,
                    projectPath: projectPath,
                    sessionID: sessionID,
                    startingAt: Date()
                )
                let responseItem = insertAssistantMessage(
                    timestamp: responseTimestamp,
                    content: responseText,
                    sessionID: sessionID,
                    projectPath: projectPath,
                    modelContext: modelContext
                )
                let responseItemValue = responseItem.toItem()
                appendSessionCompactionSummaryItemIfNeeded(
                    modelContext: modelContext,
                    sessionAgent: sessionAgent,
                    projectPath: projectPath,
                    sessionID: sessionID,
                    conversationItems: conversationItems + [userMessageItem, responseItemValue]
                )
                persist()
            } catch {
                let responseTimestamp = appendSessionToolExecutionItems(
                    modelContext: modelContext,
                    sessionAgent: sessionAgent,
                    projectPath: projectPath,
                    sessionID: sessionID,
                    startingAt: Date()
                )
                _ = insertAssistantMessage(
                    timestamp: responseTimestamp,
                    content: L10n.tr("chat.compaction_failed", error.localizedDescription),
                    sessionID: sessionID,
                    projectPath: projectPath,
                    modelContext: modelContext
                )
                persist()
            }
        }
        sessionAgent.registerCurrentTask(task)
    }

    private func compactInstructions(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "/compact"
        guard trimmed.lowercased().hasPrefix(prefix) else { return nil }
        let remainder = trimmed.dropFirst(prefix.count)
        let instructions = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        return instructions.isEmpty ? nil : instructions
    }

    private func buildContinuationPrelude(from items: [Item]) -> String? {
        guard !items.isEmpty else { return nil }

        let transcriptLines = items
            .filter { $0.kindEnum == .userMessage || $0.kindEnum == .assistantMessage }
            .suffix(8)
            .compactMap { item -> String? in
                let role = item.isUser ? "用户" : "助手"
                let content = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
                return content.isEmpty ? nil : "[\(role)] \(content)"
            }

        let summary = items
            .last(where: { $0.kindEnum == .compactionSummary })?
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

    @discardableResult
    private func appendSessionToolExecutionItems(
        modelContext: ModelContext,
        sessionAgent: SessionAgent,
        projectPath: String,
        sessionID: String,
        startingAt timestamp: Date
    ) -> Date {
        var nextTimestamp = timestamp

        for execution in sessionAgent.latestToolExecutions {
            _ = insertToolRun(
                execution: execution,
                timestamp: nextTimestamp,
                sessionID: sessionID,
                projectPath: projectPath,
                modelContext: modelContext
            )
            nextTimestamp = nextTimestamp.addingTimeInterval(0.001)
        }

        return nextTimestamp
    }

    private func appendSessionCompactionSummaryItemIfNeeded(
        modelContext: ModelContext,
        sessionAgent: SessionAgent,
        projectPath: String,
        sessionID: String,
        conversationItems: [Item]
    ) {
        guard let summary = sessionAgent.latestCompactionSummary,
              !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return
        }

        let lastPersistedSummary = conversationItems
            .filter { $0.kindEnum == .compactionSummary }
            .last?
            .content
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard summary != lastPersistedSummary else { return }

        _ = insertCompactionSummary(
            content: summary,
            sessionID: sessionID,
            projectPath: projectPath,
            modelContext: modelContext
        )
    }

    private func updateAgentProjectDirectory(agent: AgentManager) {
        agent.setActiveProjectPath(selectedProjectPath)
    }

    private func ensureProjectSelection(agent: AgentManager) {
        guard let firstProjectPath = persistedProjects.first?.path else {
            selectedProjectPath = nil
            selectedSessionID = nil
            updateAgentProjectDirectory(agent: agent)
            return
        }

        let hasSelectedProject = selectedProjectPath.map { path in
            persistedProjects.contains(where: { $0.path == path })
        } ?? false

        guard !hasSelectedProject else {
            updateAgentProjectDirectory(agent: agent)
            return
        }

        selectedProjectPath = firstProjectPath
        selectedSessionID = nil
        updateAgentProjectDirectory(agent: agent)
    }
}

private struct DisplayedRowsCacheKey: Equatable {
    let sessionID: String?
    let count: Int
    let lastTimestamp: Date?
    let firstItemID: Int?
}

private struct FlattenCacheKey: Equatable {
    let sessionCount: Int
    let messageCount: Int
    let toolRunCount: Int
    let summaryCount: Int
}
