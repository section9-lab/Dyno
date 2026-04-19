import SwiftCodingAgent
import Combine
import Foundation
import SwiftData
import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var showConfigSheet: Bool = false
    @Published var selectedSidebarMessageID: String?
    @Published var showRenameDialog: Bool = false
    @Published var renamingItemID: String?
    @Published var renameDraft: String = ""

    @Published var sidebarWidth: CGFloat = 260
    @Published var isSidebarCollapsed: Bool = false
    @Published var lastExpandedSidebarWidth: CGFloat = 260
    @Published var dragSidebarStartWidth: CGFloat?

    @Published var isImportingSessionFiles: Bool = false

    private let historyService = ChatHistoryService()

    func conversations(from items: [Item]) -> [ConversationThread] {
        historyService.buildConversations(from: items)
    }

    func sortedConversations(from items: [Item]) -> [ConversationThread] {
        historyService.sortByRecency(conversations(from: items))
    }

    func selectedConversation(from items: [Item]) -> ConversationThread? {
        historyService.selectedConversation(
            selectedID: selectedSidebarMessageID,
            conversations: conversations(from: items)
        )
    }

    func displayedItems(from items: [Item]) -> [Item] {
        historyService.displayedItems(
            selectedID: selectedSidebarMessageID,
            conversations: conversations(from: items)
        )
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

    func startNewChat(agent: AgentManager) {
        selectedSidebarMessageID = nil
        inputText = ""
        agent.latestToolExecutions = []
        agent.latestCompactionSummary = nil
        agent.refreshRuntimeContext()
    }

    func loadConversationsFromSessionFilesIfNeeded(
        items: [Item],
        modelContext: ModelContext,
        agent: AgentManager
    ) {
        guard items.isEmpty else { return }

        let snapshots = agent.loadPersistedConversations()
        guard !snapshots.isEmpty else { return }

        isImportingSessionFiles = true
        defer { isImportingSessionFiles = false }

        historyService.restoreSnapshots(snapshots, into: modelContext)
    }

    func persistConversationsToSessionFiles(items: [Item], agent: AgentManager) {
        let snapshots = historyService.makeSessionSnapshots(from: sortedConversations(from: items))
        agent.persistConversations(snapshots)
    }

    func requestRename(_ conversation: ConversationThread) {
        renamingItemID = conversation.id
        renameDraft = conversation.title
        showRenameDialog = true
    }

    @discardableResult
    func applyRename(items: [Item]) -> Bool {
        guard let id = renamingItemID else { return false }

        let didRename = historyService.renameConversation(
            id: id,
            newTitle: renameDraft,
            conversations: conversations(from: items)
        )
        guard didRename else { return false }

        renamingItemID = nil
        return true
    }

    func deleteConversation(_ conversation: ConversationThread, items: [Item], modelContext: ModelContext) {
        historyService.deleteConversation(conversation, from: modelContext)

        if selectedSidebarMessageID == conversation.id {
            selectedSidebarMessageID = sortedConversations(from: items)
                .first(where: { $0.id != conversation.id })?
                .id
        }
    }

    func sendMessage(
        modelContext: ModelContext,
        agent: AgentManager,
        conversationItems: [Item],
        persist: @escaping () -> Void
    ) {
        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        if trimmedText.lowercased().hasPrefix("/compact") {
            handleCompactCommand(
                input: trimmedText,
                modelContext: modelContext,
                agent: agent,
                conversationItems: conversationItems,
                persist: persist
            )
            return
        }

        let contextPrelude = buildContinuationPrelude(from: conversationItems)
        let conversationID = selectedSidebarMessageID ?? UUID().uuidString
        let userMessage = Item(
            timestamp: Date(),
            content: trimmedText,
            isUser: true,
            kind: "user_message",
            conversationID: conversationID
        )
        modelContext.insert(userMessage)
        selectedSidebarMessageID = conversationID
        inputText = ""
        agent.latestToolExecutions = []
        persist()

        Task {
            do {
                let response = try await agent.chat(prompt: trimmedText, contextPrelude: contextPrelude)
                let aiResponse = Item(
                    timestamp: Date(),
                    content: response,
                    isUser: false,
                    kind: "assistant_message",
                    conversationID: conversationID
                )
                modelContext.insert(aiResponse)
                appendAgentTraceItems(
                    modelContext: modelContext,
                    agent: agent,
                    conversationID: conversationID,
                    conversationItems: conversationItems + [aiResponse]
                )
                persist()
            } catch {
                let errorResponse = Item(
                    timestamp: Date(),
                    content: "抱歉，出错了：\(error.localizedDescription)",
                    isUser: false,
                    kind: "assistant_message",
                    conversationID: conversationID
                )
                modelContext.insert(errorResponse)
                persist()
            }
        }
    }

    private func handleCompactCommand(
        input: String,
        modelContext: ModelContext,
        agent: AgentManager,
        conversationItems: [Item],
        persist: @escaping () -> Void
    ) {
        let conversationID = selectedSidebarMessageID ?? UUID().uuidString
        let userMessage = Item(
            timestamp: Date(),
            content: input,
            isUser: true,
            kind: "user_message",
            conversationID: conversationID
        )
        modelContext.insert(userMessage)
        selectedSidebarMessageID = conversationID
        inputText = ""
        agent.latestToolExecutions = []
        persist()

        let instructions = compactInstructions(from: input)

        Task {
            do {
                let summary = try await agent.compact(customInstructions: instructions)
                let responseText: String
                if let summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    responseText = "已完成上下文压缩。"
                } else {
                    responseText = "当前内容不足以生成压缩摘要。"
                }

                let responseItem = Item(
                    timestamp: Date(),
                    content: responseText,
                    isUser: false,
                    kind: "assistant_message",
                    conversationID: conversationID
                )
                modelContext.insert(responseItem)
                appendAgentTraceItems(
                    modelContext: modelContext,
                    agent: agent,
                    conversationID: conversationID,
                    conversationItems: conversationItems + [responseItem]
                )
                persist()
            } catch {
                let errorResponse = Item(
                    timestamp: Date(),
                    content: "抱歉，压缩失败：\(error.localizedDescription)",
                    isUser: false,
                    kind: "assistant_message",
                    conversationID: conversationID
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
            .map { item in
                let role = item.isUser ? "用户" : "助手"
                let content = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
                return content.isEmpty ? nil : "[\(role)] \(content)"
            }
            .compactMap { $0 }

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
        conversationID: String,
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
                        conversationID: conversationID
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
                conversationID: conversationID
            )
        )
    }
}
