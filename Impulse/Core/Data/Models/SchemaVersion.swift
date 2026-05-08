import Foundation

/// Monotonically increasing integer that identifies the SwiftData entity
/// layout this build expects. Bump it whenever you change anything in
/// `Core/Data/Models/` that affects the on-disk schema:
///
///   - Add or remove an `@Model` class
///   - Add, remove, or rename a stored property
///   - Change a `@Relationship` rule
///   - Change `@Attribute(.unique)` placement
///
/// Renaming a property without changing storage (e.g. via `#oldName`)
/// does NOT need a bump — it's a binary-compatible rename.
///
/// Backups carry a copy of this number (in `<backup-folder>/schema.json`).
/// `StoreBackupManager.restore(...)` rejects backups whose version doesn't
/// match — restoring a v3 backup into a v4 app would corrupt the SwiftData
/// store on first read.
///
/// HISTORY:
///   v1 — Single `Item` entity (deprecated; existed before this constant).
///   v2 — Split into StoredSession + StoredMessage + StoredToolRun
///        + StoredCompactionSummary with cascade relationships.
///   v3 — Added StoredProject + StoredKanbanTask. ProjectSnapshot/Kanban
///        JSON persistence removed; everything now lives in SwiftData.
///   v4 — Added StoredTodoSnapshot for per-session todo state from
///        SwiftHarnessAgent's `todo_write` productivity tool. Inverse
///        relationship added on StoredSession.
enum SchemaVersion {
    static let current: Int = 4
}
