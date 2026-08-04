import Foundation
import SwiftData

// MARK: - SwiftData entities (the on-disk truth)

/// A project that the user has added to the app. Path-keyed; the on-disk
/// folder this points at can move or disappear (see `isMissing`).
@available(macOS 14.0, *)
@Model
final class StoredProject {
    @Attribute(.unique) var path: String
    var addedAt: Date

    init(path: String, addedAt: Date = Date()) {
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
