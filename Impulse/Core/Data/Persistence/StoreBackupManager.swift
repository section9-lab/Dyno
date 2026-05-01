import Foundation
import SwiftData

/// Maintains a rolling daily backup of the SwiftData store so that:
///   1. A failed schema migration can be reverted by restoring yesterday's copy
///   2. Users who report "my chats are gone" have a recoverable artifact
///   3. Developers iterating on schema changes don't fear destroying real data
///
/// Strategy:
///   - One backup per calendar day. A marker file (`last_backup_date.txt`)
///     records the date of the last run; subsequent same-day launches skip.
///   - Backups live under `~/Library/Application Support/<bundleID>/store-backups/`
///     in folders named by ISO date. Outside the SwiftData store directory so
///     SwiftData never tries to open them.
///   - Copies all three sqlite components (`.store`, `.store-shm`, `.store-wal`).
///   - Keeps the most recent `keepCount` (default 7) days; older folders deleted.
///
/// MUST be invoked **before** `ModelContainer` opens the store — once the
/// container is up, the file has open handles and the copy may be inconsistent.
struct StoreBackupManager {
    let storeURL: URL
    let backupRoot: URL
    let keepCount: Int
    /// Schema version stamped into new backups. Tests can override; production
    /// always uses `SchemaVersion.current`.
    let schemaVersion: Int

    /// Default-configured manager pointing at the SwiftData default store
    /// location.
    ///
    /// SwiftData's default `ModelConfiguration` (no `url:` argument) writes
    /// to `~/Library/Application Support/default.store` directly — *not*
    /// inside a bundle-id subfolder. Only the backup folder lives under the
    /// bundle-id-scoped subdirectory we own.
    ///
    /// IMPORTANT: If `ModelConfiguration` ever starts taking an explicit
    /// `url:`, update both call sites together — the `fileExists` guard in
    /// `runDailyBackupIfNeeded` will silently no-op otherwise.
    static func `default`(keepCount: Int = 7) -> StoreBackupManager? {
        guard let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }
        let bundleID = Bundle.main.bundleIdentifier ?? "Impulse"
        let storeURL = appSupport.appendingPathComponent("default.store", isDirectory: false)
        // Backups live in our own subdirectory so SwiftData never tries to
        // open them.
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

    init(storeURL: URL, backupRoot: URL, keepCount: Int, schemaVersion: Int = SchemaVersion.current) {
        self.storeURL = storeURL
        self.backupRoot = backupRoot
        self.keepCount = keepCount
        self.schemaVersion = schemaVersion
    }

    /// Run a backup if the marker says we haven't already done one today.
    /// Safe to call from `ImpulseApp.init` — never throws, never blocks.
    func runDailyBackupIfNeeded(now: Date = Date()) {
        let fileManager = FileManager.default

        // No store yet → first launch; nothing to back up.
        guard fileManager.fileExists(atPath: storeURL.path) else { return }

        let today = isoDate(from: now)
        if today == lastBackupDate() {
            AppLog.persistence.debug("Daily store backup already done for \(today, privacy: .public); skipping")
            return
        }

        do {
            try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)
            let dest = backupRoot.appendingPathComponent(today, isDirectory: true)

            // If a backup folder for today already exists (partial from a prior
            // attempt), nuke it before retrying.
            if fileManager.fileExists(atPath: dest.path) {
                try? fileManager.removeItem(at: dest)
            }
            try fileManager.createDirectory(at: dest, withIntermediateDirectories: true)

            // SwiftData uses sqlite WAL mode → need the trio.
            for suffix in ["", "-shm", "-wal"] {
                let src = URL(fileURLWithPath: storeURL.path + suffix)
                guard fileManager.fileExists(atPath: src.path) else { continue }
                let target = dest.appendingPathComponent(src.lastPathComponent, isDirectory: false)
                try fileManager.copyItem(at: src, to: target)
            }

            // Stamp the backup with the schema version this build understands.
            // Restoring into a future build that has bumped SchemaVersion.current
            // will be rejected before SwiftData ever tries to open the file.
            try writeSchemaStamp(at: dest, version: schemaVersion)

            try writeMarker(today)
            pruneOldBackups()

            AppLog.persistence.notice("Created store backup at \(dest.path, privacy: .public)")
        } catch {
            AppLog.persistence.error("Store backup failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Internal helpers

    private func isoDate(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    private var markerURL: URL {
        backupRoot.appendingPathComponent("last_backup_date.txt", isDirectory: false)
    }

    private func lastBackupDate() -> String? {
        guard let data = try? Data(contentsOf: markerURL),
              let raw = String(data: data, encoding: .utf8)
        else { return nil }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func writeMarker(_ date: String) throws {
        try Data(date.utf8).write(to: markerURL, options: .atomic)
    }

    private func pruneOldBackups() {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: backupRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        let dayFolders = entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent > $1.lastPathComponent } // newest first

        guard dayFolders.count > keepCount else { return }
        for url in dayFolders.dropFirst(keepCount) {
            do {
                try fileManager.removeItem(at: url)
                AppLog.persistence.debug("Pruned old store backup \(url.lastPathComponent, privacy: .public)")
            } catch {
                AppLog.persistence.error("Failed to prune backup \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Listing

    struct BackupEntry: Identifiable, Equatable {
        /// ISO date string (yyyy-MM-dd), used as the directory name. Stable;
        /// safe as a SwiftUI `Identifiable` id.
        let id: String
        let url: URL
        /// Sum of all sqlite component sizes. Useful UX info ("how big is
        /// this backup before I commit to restoring it").
        let sizeBytes: Int64
        /// Schema version at the time this backup was written. `nil` for
        /// legacy backups created before schema stamping was introduced —
        /// callers should treat them as "unknown" and warn on restore.
        let schemaVersion: Int?

        var date: Date? {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone.current
            return formatter.date(from: id)
        }
    }

    /// All available daily backups, newest first.
    func listBackups() -> [BackupEntry] {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: backupRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .compactMap { folder -> BackupEntry? in
                let id = folder.lastPathComponent
                guard isISODate(id) else { return nil } // ignore unrelated folders
                let size = totalSize(of: folder)
                let version = readSchemaStamp(at: folder)
                return BackupEntry(id: id, url: folder, sizeBytes: size, schemaVersion: version)
            }
            .sorted { $0.id > $1.id }
    }

    // MARK: - Restore

    enum RestoreError: LocalizedError {
        case backupNotFound
        case backupHasNoStoreFile
        /// Backup was written by a different schema version. Restoring would
        /// produce a store the current build can't open. Restore is blocked
        /// to protect the user; they need to install the older app version
        /// (or wait for a migration path).
        case schemaMismatch(backup: Int, current: Int)
        /// Backup has no schema stamp (predates schema-versioning). Caller
        /// can choose to ignore and proceed at their own risk.
        case schemaUnknown
        case copyFailed(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .backupNotFound: return "The selected backup folder no longer exists."
            case .backupHasNoStoreFile: return "The selected backup is missing the main store file."
            case .schemaMismatch(let backup, let current):
                return "This backup was created with a different data layout (schema v\(backup)) than the current app (v\(current)). Restoring would prevent Impulse from opening."
            case .schemaUnknown:
                return "This backup is missing schema-version metadata. It may have been created before schema versioning existed."
            case .copyFailed(let err): return "Failed to copy backup files: \(err.localizedDescription)"
            }
        }
    }

    /// Restore the SwiftData store from a backup folder.
    ///
    /// **REQUIRES the app to be quit first** (or at minimum: the
    /// `ModelContainer` to be released). With the container open, sqlite has
    /// the file mapped/locked and overwriting it produces a corrupt result.
    /// Caller is responsible for showing a "please restart" prompt.
    ///
    /// Safety procedure:
    ///   1. Validate schema stamp matches current build (refuse mismatch).
    ///   2. Snapshot the current live store to `pre-restore-<timestamp>`
    ///      so a bad restore is itself reversible.
    ///   3. Delete the live store trio.
    ///   4. Copy backup trio to live store paths.
    ///   5. On any failure mid-flight, swap the pre-restore snapshot back in.
    ///
    /// `allowUnknownSchema`: pass `true` to accept legacy backups that have
    /// no schema stamp. The Diagnostics UI surfaces this as an extra
    /// confirmation step.
    func restore(from backup: BackupEntry, allowUnknownSchema: Bool = false) throws {
        let fileManager = FileManager.default

        // Step 0: schema check. Refuse mismatches outright; let the caller
        // decide on missing stamps (legacy backups).
        switch backup.schemaVersion {
        case .some(let v) where v != schemaVersion:
            throw RestoreError.schemaMismatch(backup: v, current: schemaVersion)
        case .none where !allowUnknownSchema:
            throw RestoreError.schemaUnknown
        default:
            break
        }

        // Step 1: validate backup looks complete.
        let backupStore = backup.url.appendingPathComponent("default.store", isDirectory: false)
        guard fileManager.fileExists(atPath: backupStore.path) else {
            throw RestoreError.backupHasNoStoreFile
        }
        guard fileManager.fileExists(atPath: backup.url.path) else {
            throw RestoreError.backupNotFound
        }

        // Step 1: snapshot the live store (if any) into a safety folder.
        let safetyFolder = backupRoot.appendingPathComponent(
            "pre-restore-\(Int(Date().timeIntervalSince1970))",
            isDirectory: true
        )

        do {
            try fileManager.createDirectory(at: safetyFolder, withIntermediateDirectories: true)
            for suffix in ["", "-shm", "-wal"] {
                let src = URL(fileURLWithPath: storeURL.path + suffix)
                guard fileManager.fileExists(atPath: src.path) else { continue }
                let target = safetyFolder.appendingPathComponent(src.lastPathComponent)
                try fileManager.copyItem(at: src, to: target)
            }
        } catch {
            // We failed even before touching the live store — abort cleanly.
            throw RestoreError.copyFailed(underlying: error)
        }

        // Step 2 + 3: delete + copy. Any failure → roll back from safetyFolder.
        do {
            for suffix in ["", "-shm", "-wal"] {
                let liveURL = URL(fileURLWithPath: storeURL.path + suffix)
                if fileManager.fileExists(atPath: liveURL.path) {
                    try fileManager.removeItem(at: liveURL)
                }
            }
            for suffix in ["", "-shm", "-wal"] {
                let src = backup.url.appendingPathComponent("default.store" + suffix)
                guard fileManager.fileExists(atPath: src.path) else { continue }
                let target = URL(fileURLWithPath: storeURL.path + suffix)
                try fileManager.copyItem(at: src, to: target)
            }
            AppLog.persistence.notice("Restored SwiftData store from backup \(backup.id, privacy: .public)")
        } catch {
            AppLog.persistence.error("Restore failed mid-flight, rolling back: \(error.localizedDescription, privacy: .public)")
            try? rollback(from: safetyFolder)
            throw RestoreError.copyFailed(underlying: error)
        }
    }

    private func rollback(from safety: URL) throws {
        let fileManager = FileManager.default
        for suffix in ["", "-shm", "-wal"] {
            let liveURL = URL(fileURLWithPath: storeURL.path + suffix)
            if fileManager.fileExists(atPath: liveURL.path) {
                try? fileManager.removeItem(at: liveURL)
            }
        }
        for suffix in ["", "-shm", "-wal"] {
            let snap = safety.appendingPathComponent("default.store" + suffix)
            guard fileManager.fileExists(atPath: snap.path) else { continue }
            let target = URL(fileURLWithPath: storeURL.path + suffix)
            try fileManager.copyItem(at: snap, to: target)
        }
    }

    // MARK: - Helpers

    private func isISODate(_ s: String) -> Bool {
        guard s.count == 10 else { return false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: s) != nil
    }

    private func totalSize(of folder: URL) -> Int64 {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }

        var total: Int64 = 0
        for url in entries {
            // Schema-stamp metadata isn't user data; excluding it keeps the
            // displayed size honest ("how big is my chat history" rather than
            // "how big is the folder").
            if url.lastPathComponent == Self.schemaStampFilename { continue }
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    // MARK: - Schema stamp

    /// Schema-stamp file written into each backup folder. JSON so a future
    /// version can add fields (e.g. app build, last-migration-id) without
    /// breaking older readers.
    private static let schemaStampFilename = "schema.json"

    private struct SchemaStamp: Codable {
        let version: Int
    }

    private func writeSchemaStamp(at folder: URL, version: Int) throws {
        let url = folder.appendingPathComponent(Self.schemaStampFilename)
        let data = try JSONEncoder().encode(SchemaStamp(version: version))
        try data.write(to: url, options: .atomic)
    }

    /// Reads the schema stamp from a backup folder. Returns `nil` for
    /// legacy backups created before stamping was introduced.
    private func readSchemaStamp(at folder: URL) -> Int? {
        let url = folder.appendingPathComponent(Self.schemaStampFilename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONDecoder().decode(SchemaStamp.self, from: data))?.version
    }
}
