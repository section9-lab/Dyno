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

    @Published var newKanbanTitle: String = ""
    @Published var newKanbanPriority: KanbanTaskPriority = .medium

    private let historyService = ChatHistoryService()
    private let sandboxAccess = SandboxAccessManager.shared

    func loadProjects(agent: AgentManager) {
        persistedProjects = agent.loadPersistedProjects()
        expandedProjectPaths.formUnion(persistedProjects.map(\.path))
        ensureProjectSelection(agent: agent)
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
        agent.latestToolExecutions = []
        agent.latestCompactionSummary = nil
        updateAgentProjectDirectory(agent: agent)
        return true
    }

    func addProject(agent: AgentManager) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Add Project"
        panel.message = "选择一个本地目录作为项目"

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
    }

    func createKanbanTask() {
        guard let projectPath = selectedProjectPath else { return }
        let title = newKanbanTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        let linkedSessionIDs = selectedSessionID.map { [$0] } ?? []
        let task = KanbanTaskSnapshot(
            id: UUID().uuidString,
            projectPath: projectPath,
            title: title,
            status: .plan,
            priority: newKanbanPriority,
            primarySessionID: selectedSessionID,
            linkedSessionIDs: linkedSessionIDs,
            assigneeName: "AI",
            notes: "",
            createdAt: Date(),
            updatedAt: Date()
        )

        historyService.upsertKanbanTask(task, persistedProjects: &persistedProjects)
        newKanbanTitle = ""
        newKanbanPriority = .medium
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
    func applyRename(items: [Item]) -> Bool {
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
            persistedProjects: &persistedProjects
        )
        guard didRename else { return false }

        renamingSessionID = nil
        return true
    }

    func deleteSession(_ session: ChatSession, modelContext: ModelContext) {
        historyService.deleteSession(
            projectPath: session.projectPath,
            sessionID: session.id,
            persistedProjects: &persistedProjects,
            modelContext: modelContext
        )

        if selectedSessionID == session.id {
            selectedSessionID = nil
        }
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
        let userMessage = Item(
            timestamp: Date(),
            content: trimmedText,
            isUser: true,
            kind: "user_message",
            conversationID: session.id,
            projectPath: projectPath
        )
        modelContext.insert(userMessage)
        inputText = ""
        agent.latestToolExecutions = []
        persist()

        Task {
            do {
                let response = try await agent.sendChat(prompt: trimmedText, contextPrelude: contextPrelude)
                let aiResponse = Item(
                    timestamp: Date(),
                    content: response,
                    isUser: false,
                    kind: "assistant_message",
                    conversationID: session.id,
                    projectPath: projectPath
                )
                modelContext.insert(aiResponse)
                appendAgentTraceItems(
                    modelContext: modelContext,
                    agent: agent,
                    projectPath: projectPath,
                    sessionID: session.id,
                    conversationItems: conversationItems + [aiResponse]
                )
                persist()
            } catch {
                let errorResponse = Item(
                    timestamp: Date(),
                    content: "抱歉，出错了：\(error.localizedDescription)",
                    isUser: false,
                    kind: "assistant_message",
                    conversationID: session.id,
                    projectPath: projectPath
                )
                modelContext.insert(errorResponse)
                persist()
            }
        }
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
        let userMessage = Item(
            timestamp: Date(),
            content: input,
            isUser: true,
            kind: "user_message",
            conversationID: sessionID,
            projectPath: projectPath
        )
        modelContext.insert(userMessage)
        inputText = ""
        agent.latestToolExecutions = []
        persist()

        let instructions = compactInstructions(from: input)

        Task {
            do {
                let summary = try await agent.compact(customInstructions: instructions)
                let responseText = if let summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    "已完成上下文压缩。"
                } else {
                    "当前内容不足以生成压缩摘要。"
                }

                let responseItem = Item(
                    timestamp: Date(),
                    content: responseText,
                    isUser: false,
                    kind: "assistant_message",
                    conversationID: sessionID,
                    projectPath: projectPath
                )
                modelContext.insert(responseItem)
                appendAgentTraceItems(
                    modelContext: modelContext,
                    agent: agent,
                    projectPath: projectPath,
                    sessionID: sessionID,
                    conversationItems: conversationItems + [responseItem]
                )
                persist()
            } catch {
                let errorResponse = Item(
                    timestamp: Date(),
                    content: "抱歉，压缩失败：\(error.localizedDescription)",
                    isUser: false,
                    kind: "assistant_message",
                    conversationID: sessionID,
                    projectPath: projectPath
                )
                modelContext.insert(errorResponse)
                persist()
            }
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

    private func buildContinuationPrelude(from items: [Item]) -> String? {
        guard !items.isEmpty else { return nil }

        let transcriptLines = items
            .filter { $0.kind == "user_message" || $0.kind == "assistant_message" }
            .suffix(8)
            .compactMap { item -> String? in
                let role = item.isUser ? "用户" : "助手"
                let content = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
                return content.isEmpty ? nil : "[\(role)] \(content)"
            }

        let summary = items
            .last(where: { $0.kind == "compaction_summary" })?
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

    private func appendAgentTraceItems(
        modelContext: ModelContext,
        agent: AgentManager,
        projectPath: String,
        sessionID: String,
        conversationItems: [Item]
    ) {
        for execution in agent.latestToolExecutions {
            let payload = PersistedToolExecution(
                id: execution.id,
                toolName: execution.toolName,
                status: execution.status.rawValue,
                summary: execution.summary,
                output: execution.output
            )
            if let data = try? JSONEncoder().encode(payload),
               let text = String(data: data, encoding: .utf8)
            {
                modelContext.insert(
                    Item(
                        timestamp: Date(),
                        content: text,
                        isUser: false,
                        kind: "tool_execution",
                        conversationID: sessionID,
                        projectPath: projectPath
                    )
                )
            }
        }

        guard let summary = agent.latestCompactionSummary,
              !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return
        }

        let lastPersistedSummary = conversationItems
            .filter { $0.kind == "compaction_summary" }
            .last?
            .content
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard summary != lastPersistedSummary else { return }

        modelContext.insert(
            Item(
                timestamp: Date(),
                content: summary,
                isUser: false,
                kind: "compaction_summary",
                conversationID: sessionID,
                projectPath: projectPath
            )
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
