import Foundation

struct ChatSession: Identifiable {
    let id: String
    let projectPath: String
    let title: String
    let startedAt: Date
    let messages: [Item]
}

struct ChatProject: Identifiable {
    let id: String
    let path: String
    let name: String
    let sessions: [ChatSession]
    let kanbanTasks: [KanbanTaskSnapshot]

    var isMissing: Bool {
        !FileManager.default.fileExists(atPath: path)
    }
}
