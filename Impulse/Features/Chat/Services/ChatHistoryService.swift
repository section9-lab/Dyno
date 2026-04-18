import Foundation
import SwiftData

/// 业务层：负责聊天记录的会话划分、重命名/删除规则，以及与 session 快照之间的转换。
///
/// 说明：
/// - 不依赖 AgentSDK
/// - 不处理模型调用
/// - 仅处理 Item（业务消息）与会话语义
struct ChatHistoryService {
    func buildConversations(from items: [Item]) -> [ConversationThread] {
        let sorted = items
            .filter { supportedKinds.contains($0.kind) }
            .sorted { $0.timestamp < $1.timestamp }

        var grouped: [String: [Item]] = [:]
        var orderedIDs: [String] = []
        var legacyIndex = 0
        var currentLegacyID: String?

        for message in sorted {
            let conversationID: String
            if !message.conversationID.isEmpty {
                conversationID = message.conversationID
                currentLegacyID = nil
            } else {
                if message.isUser || currentLegacyID == nil {
                    currentLegacyID = "legacy-\(legacyIndex)"
                    legacyIndex += 1
                }
                conversationID = currentLegacyID ?? "legacy-\(legacyIndex)"
            }

            if grouped[conversationID] == nil {
                grouped[conversationID] = []
                orderedIDs.append(conversationID)
            }
            grouped[conversationID, default: []].append(message)
        }

        return orderedIDs.compactMap { conversationID in
            guard let messages = grouped[conversationID], !messages.isEmpty else { return nil }
            let orderedMessages = messages.sorted { $0.timestamp < $1.timestamp }
            guard let first = orderedMessages.first else { return nil }

            let firstUser = orderedMessages.first(where: { $0.isUser })
            let titleSource = firstUser?.content ?? first.content
            let title = normalizedTitle(from: titleSource)

            return ConversationThread(
                id: conversationID,
                title: title,
                startedAt: first.timestamp,
                messages: orderedMessages
            )
        }
    }

    func sortByRecency(_ conversations: [ConversationThread]) -> [ConversationThread] {
        conversations.sorted { $0.startedAt > $1.startedAt }
    }

    func selectedConversation(
        selectedID: String?,
        conversations: [ConversationThread]
    ) -> ConversationThread? {
        guard let selectedID else { return nil }
        return conversations.first(where: { $0.id == selectedID })
    }

    func displayedItems(selectedID: String?, conversations: [ConversationThread]) -> [Item] {
        selectedConversation(selectedID: selectedID, conversations: conversations)?.messages ?? []
    }

    @discardableResult
    func renameConversation(
        id: String,
        newTitle: String,
        conversations: [ConversationThread]
    ) -> Bool {
        let normalized = normalizedTitle(from: newTitle)
        guard normalized != "(empty)",
              let conversation = conversations.first(where: { $0.id == id })
        else {
            return false
        }

        if let firstUser = conversation.messages.first(where: { $0.isUser }) {
            firstUser.content = normalized
            return true
        }

        if let first = conversation.messages.first {
            first.content = normalized
            return true
        }

        return false
    }

    func deleteConversation(_ conversation: ConversationThread, from modelContext: ModelContext) {
        for message in conversation.messages {
            modelContext.delete(message)
        }
    }

    func makeSessionSnapshots(from conversations: [ConversationThread]) -> [SessionConversationSnapshot] {
        conversations.map { conversation in
            SessionConversationSnapshot(
                id: conversation.id,
                title: conversation.title,
                startedAt: conversation.startedAt,
                messages: conversation.messages
                    .filter { supportedKinds.contains($0.kind) }
                    .map { message in
                        SessionMessageSnapshot(
                            role: message.isUser ? "user" : "assistant",
                            content: message.content,
                            timestamp: message.timestamp,
                            kind: message.kind
                        )
                    }
            )
        }
    }

    func restoreSnapshots(_ snapshots: [SessionConversationSnapshot], into modelContext: ModelContext) {
        for snapshot in snapshots.reversed() {
            for message in snapshot.messages where supportedKinds.contains(message.kind) {
                modelContext.insert(
                    Item(
                        timestamp: message.timestamp,
                        content: message.content,
                        isUser: message.role == "user",
                        kind: message.kind,
                        conversationID: snapshot.id
                    )
                )
            }
        }
    }

    private let supportedKinds: Set<String> = ["user_message", "assistant_message", "tool_execution", "compaction_summary"]

    private func normalizedTitle(from raw: String) -> String {
        let singleLine = raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return singleLine.isEmpty ? "(empty)" : singleLine
    }
}
