import Foundation

struct SessionMessageSnapshot: Codable {
    let role: String
    let content: String
    let timestamp: Date
    let kind: String
}

struct ProjectSessionSnapshot: Identifiable, Codable {
    let id: String
    let projectPath: String
    let title: String
    let startedAt: Date
    let messages: [SessionMessageSnapshot]
}

struct ProjectSnapshot: Identifiable, Codable {
    let id: String
    let path: String
    let addedAt: Date
    let sessions: [ProjectSessionSnapshot]
    let kanbanTasks: [KanbanTaskSnapshot]
}
