import Foundation
import PiWorkCore

extension StoreBackupManager {
    static func `default`(keepCount: Int = 7) -> StoreBackupManager? {
        guard let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }
        let bundleID = Bundle.main.bundleIdentifier ?? "pi-work"
        let storeURL = appSupport.appendingPathComponent("default.store", isDirectory: false)
        // Backups live in our own subdirectory so the persistence layer
        // never tries to open them as a live store.
        let backupRoot = appSupport
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("store-backups", isDirectory: true)
        return StoreBackupManager(
            storeURL: storeURL,
            backupRoot: backupRoot,
            keepCount: keepCount,
            schemaVersion: SchemaVersion.current
        )
    }
}
