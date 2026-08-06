import Foundation
import CoreData

// MARK: - Core Data entities (the on-disk truth)

/// A project that the user has added to the app. Path-keyed; the on-disk
/// folder this points at can move or disappear (see `isMissing`).
@objc(StoredProject)
final class StoredProject: NSManagedObject {
    @NSManaged var path: String
    @NSManaged var addedAt: Date

    convenience init(context: NSManagedObjectContext, path: String, addedAt: Date = Date()) {
        self.init(context: context)
        self.path = path
        self.addedAt = addedAt
    }

    var displayName: String {
        let last = URL(fileURLWithPath: path).lastPathComponent
        return last.isEmpty ? path : last
    }

    var isMissing: Bool {
        !FileManager.default.fileExists(atPath: path)
    }
}
