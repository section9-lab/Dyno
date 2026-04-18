import Foundation

struct ConversationThread: Identifiable {
    let id: String
    let title: String
    let startedAt: Date
    let messages: [Item]
}
