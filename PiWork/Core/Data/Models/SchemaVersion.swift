import Foundation

/// Monotonically increasing integer that identifies the persistent store's
/// entity layout this build expects. Bump it whenever you change anything in
/// `Core/Data/Models/` that affects the on-disk schema.
///
/// HISTORY:
///   v1 — Single `Item` entity (deprecated; existed before this constant).
///   v2 — Split into StoredSession + StoredMessage + StoredToolRun
///        + StoredCompactionSummary with cascade relationships.
///   v3 — Added StoredProject + StoredKanbanTask. ProjectSnapshot/Kanban
///        JSON persistence removed; everything now lived in SwiftData.
///   v6 — Removed chat/agent persistence models; project + Kanban data remain.
///   v7 — Migrated the store from SwiftData to a code-defined Core Data
///        model (same entities/fields) so the app works unconditionally on
///        the project's macOS 13.0 deployment target instead of requiring
///        macOS 14+ at runtime. Old SwiftData-era backups are not restorable.
enum SchemaVersion {
    static let current: Int = 7
}
