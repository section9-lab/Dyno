import Foundation

struct SessionMessageSnapshot: Codable {
    let role: String
    let content: String
    let timestamp: Date
    let kind: String
}

struct SessionConversationSnapshot: Identifiable, Codable {
    let id: String
    let title: String
    let startedAt: Date
    let messages: [SessionMessageSnapshot]
}
