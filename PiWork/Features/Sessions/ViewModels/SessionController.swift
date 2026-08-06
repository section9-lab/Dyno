import Foundation
import CoreData

/// CRUD for the lightweight local session/journal feature. Mirrors
/// `KanbanController`'s pattern of explicit `.save()` after every mutation
/// (Core Data has no autosave-on-change like SwiftData).
struct SessionController {
    @discardableResult
    func createSession(
        title: String,
        projectPath: String,
        modelContext: NSManagedObjectContext
    ) -> StoredSession {
        let session = StoredSession(context: modelContext, projectPath: projectPath, title: title)
        try? modelContext.save()
        return session
    }

    func renameSession(_ session: StoredSession, title: String, modelContext: NSManagedObjectContext) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        session.title = trimmed
        session.updatedAt = Date()
        try? modelContext.save()
    }

    func deleteSession(
        _ session: StoredSession,
        entries: [StoredSessionEntry],
        modelContext: NSManagedObjectContext
    ) {
        for entry in entries where entry.sessionID == session.id {
            modelContext.delete(entry)
        }
        modelContext.delete(session)
        try? modelContext.save()
    }

    @discardableResult
    func addEntry(
        content: String,
        to session: StoredSession,
        modelContext: NSManagedObjectContext
    ) -> StoredSessionEntry? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let entry = StoredSessionEntry(context: modelContext, sessionID: session.id, content: trimmed)
        session.updatedAt = Date()
        try? modelContext.save()
        return entry
    }

    func deleteEntry(_ entry: StoredSessionEntry, modelContext: NSManagedObjectContext) {
        modelContext.delete(entry)
        try? modelContext.save()
    }
}
