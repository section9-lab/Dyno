import Foundation
import SwiftData

/// The kind of message/event in a chat session. Used as the source of truth
/// for both UI dispatch and the legacy on-disk JSON snapshots.
///
/// Schema-stable: do not rename existing raw values. The values below are
/// also written to `ProjectSnapshot.SessionMessageSnapshot.kind` (JSON file
/// outside the SwiftData store) and to legacy `Item.kind` rows still in
/// circulation on developer machines.
enum ItemKind: String, CaseIterable, Codable {
    case userMessage = "user_message"
    case assistantMessage = "assistant_message"
    case toolExecution = "tool_execution"
    case compactionSummary = "compaction_summary"
}

// MARK: - Item (value type — UI projection of SwiftData entities)

/// A read-only snapshot of one row in a chat transcript. Produced by
/// `ChatHistoryService` from the underlying SwiftData entities and consumed
/// by the SwiftUI views.
///
/// Why a value type, not an `@Model`:
///   - Multiple SwiftData entity types (StoredMessage, StoredToolRun,
///     StoredCompactionSummary) flatten into a single homogeneous list for
///     display ordering. Modeling that as a relational query with a UNION
///     adds complexity SwiftData doesn't natively express.
///   - Views never mutate Items — they're frozen at the moment of projection.
///   - Decouples the on-disk schema from the UI surface, so future entity
///     refactors don't immediately break every view.
///
/// Stable identity: `id` is the persistent identifier of the underlying
/// SwiftData object; same row produces the same id across re-projections.
struct Item: Identifiable, Hashable {
    let id: PersistentIdentifier
    let timestamp: Date
    var content: String
    let isUser: Bool
    let kind: String
    let conversationID: String
    let projectPath: String

    var kindEnum: ItemKind {
        ItemKind(rawValue: kind) ?? .assistantMessage
    }

    static func == (lhs: Item, rhs: Item) -> Bool {
        lhs.id == rhs.id
            && lhs.timestamp == rhs.timestamp
            && lhs.content == rhs.content
            && lhs.kind == rhs.kind
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - SwiftData entities (the on-disk truth)

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

/// A user or assistant message. Role is a string for SwiftData compatibility;
/// use `roleEnum` for type-safe access.
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
    var kind: ItemKind { isUser ? .userMessage : .assistantMessage }
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

// MARK: - Projection: SwiftData entity → Item

extension StoredMessage {
    /// Project this entity into a UI-facing `Item`.
    func toItem() -> Item {
        Item(
            id: persistentModelID,
            timestamp: timestamp,
            content: content,
            isUser: isUser,
            kind: kind.rawValue,
            conversationID: session?.id ?? "",
            projectPath: session?.projectPath ?? ""
        )
    }
}

extension StoredToolRun {
    /// Project into an Item whose `content` is the JSON-encoded
    /// `PersistedToolExecution`. This preserves the existing UI contract:
    /// tool rows ride alongside messages in the same `[Item]` list.
    func toItem() -> Item? {
        let payload = PersistedToolExecution(
            id: id,
            toolName: toolName,
            status: status,
            summary: summary,
            output: output
        )
        guard let data = try? JSONEncoder().encode(payload),
              let text = String(data: data, encoding: .utf8)
        else { return nil }

        return Item(
            id: persistentModelID,
            timestamp: timestamp,
            content: text,
            isUser: false,
            kind: ItemKind.toolExecution.rawValue,
            conversationID: session?.id ?? "",
            projectPath: session?.projectPath ?? ""
        )
    }
}

extension StoredCompactionSummary {
    func toItem() -> Item {
        Item(
            id: persistentModelID,
            timestamp: timestamp,
            content: content,
            isUser: false,
            kind: ItemKind.compactionSummary.rawValue,
            conversationID: session?.id ?? "",
            projectPath: session?.projectPath ?? ""
        )
    }
}
