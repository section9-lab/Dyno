import Foundation

public struct StoreBackupManager {
    public let storeURL: URL
    public let backupRoot: URL
    public let keepCount: Int
    public let schemaVersion: Int

    public init(storeURL: URL, backupRoot: URL, keepCount: Int, schemaVersion: Int = 1) {
        self.storeURL = storeURL
        self.backupRoot = backupRoot
        self.keepCount = keepCount
        self.schemaVersion = schemaVersion
    }

    public func runDailyBackupIfNeeded(now: Date = Date()) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: storeURL.path) else { return }

        let today = isoDate(from: now)
        if today == lastBackupDate() { return }

        do {
            try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)
            let dest = backupRoot.appendingPathComponent(today, isDirectory: true)

            if fileManager.fileExists(atPath: dest.path) {
                try? fileManager.removeItem(at: dest)
            }
            try fileManager.createDirectory(at: dest, withIntermediateDirectories: true)

            for suffix in ["", "-shm", "-wal"] {
                let src = URL(fileURLWithPath: storeURL.path + suffix)
                guard fileManager.fileExists(atPath: src.path) else { continue }
                let target = dest.appendingPathComponent(src.lastPathComponent, isDirectory: false)
                try fileManager.copyItem(at: src, to: target)
            }

            try writeSchemaStamp(at: dest, version: schemaVersion)
            try writeMarker(today)
            pruneOldBackups()
        } catch {
        }
    }

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
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        guard dayFolders.count > keepCount else { return }
        for url in dayFolders.dropFirst(keepCount) {
            try? fileManager.removeItem(at: url)
        }
    }

    public struct BackupEntry: Identifiable, Equatable {
        public let id: String
        public let url: URL
        public let sizeBytes: Int64
        public let schemaVersion: Int?

        public init(id: String, url: URL, sizeBytes: Int64, schemaVersion: Int?) {
            self.id = id
            self.url = url
            self.sizeBytes = sizeBytes
            self.schemaVersion = schemaVersion
        }

        public var date: Date? {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone.current
            return formatter.date(from: id)
        }
    }

    public func listBackups() -> [BackupEntry] {
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
                guard isISODate(id) else { return nil }
                let size = totalSize(of: folder)
                let version = readSchemaStamp(at: folder)
                return BackupEntry(id: id, url: folder, sizeBytes: size, schemaVersion: version)
            }
            .sorted { $0.id > $1.id }
    }

    public enum RestoreError: LocalizedError {
        case backupNotFound
        case backupHasNoStoreFile
        case schemaMismatch(backup: Int, current: Int)
        case schemaUnknown
        case copyFailed(underlying: Error)

        public var errorDescription: String? {
            switch self {
            case .backupNotFound: return "The selected backup folder no longer exists."
            case .backupHasNoStoreFile: return "The selected backup is missing the main store file."
            case .schemaMismatch(let backup, let current):
                return "This backup was created with a different data layout (schema v\(backup)) than the current app (v\(current)). Restoring would prevent pi-work from opening."
            case .schemaUnknown:
                return "This backup is missing schema-version metadata. It may have been created before schema versioning existed."
            case .copyFailed(let err): return "Failed to copy backup files: \(err.localizedDescription)"
            }
        }
    }

    public func restore(from backup: BackupEntry, allowUnknownSchema: Bool = false) throws {
        let fileManager = FileManager.default

        switch backup.schemaVersion {
        case .some(let v) where v != schemaVersion:
            throw RestoreError.schemaMismatch(backup: v, current: schemaVersion)
        case .none where !allowUnknownSchema:
            throw RestoreError.schemaUnknown
        default:
            break
        }

        let backupStore = backup.url.appendingPathComponent("default.store", isDirectory: false)
        guard fileManager.fileExists(atPath: backupStore.path) else {
            throw RestoreError.backupHasNoStoreFile
        }
        guard fileManager.fileExists(atPath: backup.url.path) else {
            throw RestoreError.backupNotFound
        }

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
            throw RestoreError.copyFailed(underlying: error)
        }

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
        } catch {
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
            if url.lastPathComponent == Self.schemaStampFilename { continue }
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    private static let schemaStampFilename = "schema.json"

    private struct SchemaStamp: Codable {
        let version: Int
    }

    private func writeSchemaStamp(at folder: URL, version: Int) throws {
        let url = folder.appendingPathComponent(Self.schemaStampFilename)
        let data = try JSONEncoder().encode(SchemaStamp(version: version))
        try data.write(to: url, options: .atomic)
    }

    private func readSchemaStamp(at folder: URL) -> Int? {
        let url = folder.appendingPathComponent(Self.schemaStampFilename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONDecoder().decode(SchemaStamp.self, from: data))?.version
    }
}
