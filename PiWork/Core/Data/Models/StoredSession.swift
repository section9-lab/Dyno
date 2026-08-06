import Foundation
import CoreData

/// A lightweight, purely local "session" scoped to a project — a running
/// log of freeform notes typed into an input box. Unlike the earlier
/// (removed) AI chat feature, entries are never sent anywhere or answered by
/// a model; this is just a per-project scratchpad/journal.
@objc(StoredSession)
final class StoredSession: NSManagedObject, Identifiable {
    @NSManaged var id: String
    @NSManaged var projectPath: String
    @NSManaged var title: String
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date

    convenience init(
        context: NSManagedObjectContext,
        id: String = UUID().uuidString,
        projectPath: String,
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.init(context: context)
        self.id = id
        self.projectPath = projectPath
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// One entry (a single input-box submission) within a `StoredSession`.
/// Entries are denormalised against `sessionID` — the same pattern
/// `StoredKanbanTask` uses for `projectPath` — rather than a Core Data
/// relationship.
@objc(StoredSessionEntry)
final class StoredSessionEntry: NSManagedObject, Identifiable {
    @NSManaged var id: String
    @NSManaged var sessionID: String
    @NSManaged var content: String
    @NSManaged var createdAt: Date

    convenience init(
        context: NSManagedObjectContext,
        id: String = UUID().uuidString,
        sessionID: String,
        content: String,
        createdAt: Date = Date()
    ) {
        self.init(context: context)
        self.id = id
        self.sessionID = sessionID
        self.content = content
        self.createdAt = createdAt
    }
}
