import Foundation

/// Monotonically increasing integer that identifies the SwiftData entity
/// layout this build expects. Bump it whenever you change anything in
/// `Core/Data/Models/` that affects the on-disk schema.
///
/// HISTORY:
///   v1 — Single `Item` entity (deprecated; existed before this constant).
///   v2 — Split into StoredSession + StoredMessage + StoredToolRun
///        + StoredCompactionSummary with cascade relationships.
///   v3 — Added StoredProject + StoredKanbanTask. ProjectSnapshot/Kanban
///        JSON persistence removed; everything now lives in SwiftData.
///   v4 — Added StoredTodoSnapshot for per-session todo state from
///        SwiftHarnessAgent's `todo_write` productivity tool.
///   v5 — Added StoredSubagentToolRun plus richer persisted task metadata.
///   v6 — Removed chat/agent persistence models; project + Kanban data remain.
enum SchemaVersion {
    static let current: Int = 6
}
