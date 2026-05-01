import Foundation
import SwiftData

// MARK: - SwiftData entities (the on-disk truth)

/// A project that the user has added to Impulse. Path-keyed; the on-disk
/// folder this points at can move or disappear (see `isMissing`).
///
/// Sessions and Kanban tasks live in their own entities and reference the
/// project by `projectPath` (denormalised). We don't use SwiftData
/// relationships across `StoredProject ↔ StoredSession` either — explicit
/// fetch-by-path is simpler and avoids SwiftData's inverse-relationship
/// quirks at the project level.
@Model
final class StoredProject {
    @Attribute(.unique) var path: String
    var addedAt: Date

    init(path: String, addedAt: Date = Date()) {
        self.path = path
        self.addedAt = addedAt
    }

    /// Folder name component, computed for display.
    var displayName: String {
        let last = URL(fileURLWithPath: path).lastPathComponent
        return last.isEmpty ? path : last
    }

    /// Whether the underlying folder still exists on disk. Computed; not
    /// persisted (filesystem state, not user data).
    var isMissing: Bool {
        !FileManager.default.fileExists(atPath: path)
    }
}

/// One chat session within a project. Messages, tool runs, and compaction
/// summaries hang off this entity via cascade relationships.
@Model
final class StoredSession {
    @Attribute(.unique) var id: String      // session UUID
    var projectPath: String
    var title: String
    var startedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \StoredMessage.session)
    var messages: [StoredMessage] = []

    @Relationship(deleteRule: .cascade, inverse: \StoredToolRun.session)
    var toolRuns: [StoredToolRun] = []

    @Relationship(deleteRule: .cascade, inverse: \StoredCompactionSummary.session)
    var compactionSummaries: [StoredCompactionSummary] = []

    init(id: String, projectPath: String, title: String, startedAt: Date) {
        self.id = id
        self.projectPath = projectPath
        self.title = title
        self.startedAt = startedAt
    }
}

/// A user or assistant message.
@Model
final class StoredMessage {
    var timestamp: Date
    var role: String                        // "user" | "assistant"
    var content: String
    var session: StoredSession?

    init(timestamp: Date, role: String, content: String, session: StoredSession? = nil) {
        self.timestamp = timestamp
        self.role = role
        self.content = content
        self.session = session
    }

    var isUser: Bool { role == "user" }
}

/// One tool invocation (read/write/edit/bash). The id is the SDK-provided
/// `toolCallID` so re-running the same call updates in place.
@Model
final class StoredToolRun {
    @Attribute(.unique) var id: String
    var timestamp: Date
    var toolName: String
    var status: String                      // "running" | "success" | "failed"
    var summary: String
    var output: String
    var session: StoredSession?

    init(
        id: String,
        timestamp: Date,
        toolName: String,
        status: String,
        summary: String,
        output: String,
        session: StoredSession? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.toolName = toolName
        self.status = status
        self.summary = summary
        self.output = output
        self.session = session
    }
}

/// Periodic compaction summary written by the agent loop when a session
/// reaches the model's context limit.
@Model
final class StoredCompactionSummary {
    var timestamp: Date
    var content: String
    var session: StoredSession?

    init(timestamp: Date, content: String, session: StoredSession? = nil) {
        self.timestamp = timestamp
        self.content = content
        self.session = session
    }
}
