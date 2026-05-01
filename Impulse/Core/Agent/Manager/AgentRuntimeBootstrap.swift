import Foundation

/// Owns the on-disk directory layout for the agent runtime. Creates the
/// app data / storage / skills / memory / execution-workspace directories
/// idempotently, and migrates the legacy `~/.agent` layout in-place.
///
/// Stateless — safe to call `bootstrap()` more than once.
struct AgentRuntimeBootstrap {
    var appDataDirectoryURL: URL {
        URL(fileURLWithPath: AgentServiceConfig.defaultAppDataDirectoryPath)
    }
    var storageDirectoryURL: URL {
        URL(fileURLWithPath: AgentServiceConfig.defaultStorageDirectoryPath)
    }
    var executionWorkspaceURL: URL {
        URL(fileURLWithPath: AgentServiceConfig.defaultExecutionWorkspacePath)
    }

    func bootstrap() {
        migrateLegacyAgentDataIfNeeded()
        let skillsDir = storageDirectoryURL.agentSkillsDirectory()
        let memoryDir = storageDirectoryURL.agentMemoryDirectory()
        let rawMemoryDir = memoryDir.appendingPathComponent("raw", isDirectory: true)

        for dir in [appDataDirectoryURL, storageDirectoryURL, skillsDir, memoryDir, rawMemoryDir, executionWorkspaceURL] {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                // Idempotent — directory already exists is fine; otherwise log.
                if (error as NSError).code != NSFileWriteFileExistsError {
                    AppLog.persistence.error("Failed to create \(dir.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func migrateLegacyAgentDataIfNeeded() {
        let fileManager = FileManager.default
        let legacyRoot = appDataDirectoryURL.appendingPathComponent(".agent", isDirectory: true)
        let newRoot = storageDirectoryURL

        guard legacyRoot.standardizedFileURL.path != newRoot.standardizedFileURL.path else { return }
        guard fileManager.fileExists(atPath: legacyRoot.path) else { return }
        try? fileManager.createDirectory(at: newRoot, withIntermediateDirectories: true)

        for directoryName in ["skills", "memory"] {
            let legacyURL = legacyRoot.appendingPathComponent(directoryName, isDirectory: true)
            let destinationURL = newRoot.appendingPathComponent(directoryName, isDirectory: true)
            guard fileManager.fileExists(atPath: legacyURL.path) else { continue }

            do {
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try mergeDirectoryContents(from: legacyURL, into: destinationURL)
                    try removeDirectoryIfEmpty(legacyURL)
                } else {
                    try fileManager.moveItem(at: legacyURL, to: destinationURL)
                }
            } catch {
                AppLog.persistence.error("Failed to migrate legacy agent directory \(legacyURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        try? removeDirectoryIfEmpty(legacyRoot)
    }

    private func mergeDirectoryContents(from source: URL, into destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let children = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey])

        for child in children {
            let target = destination.appendingPathComponent(child.lastPathComponent, isDirectory: false)
            if fileManager.fileExists(atPath: target.path) {
                let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDirectory {
                    try mergeDirectoryContents(from: child, into: target)
                    try removeDirectoryIfEmpty(child)
                }
            } else {
                try fileManager.moveItem(at: child, to: target)
            }
        }
    }

    private func removeDirectoryIfEmpty(_ url: URL) throws {
        let fileManager = FileManager.default
        let remaining = try fileManager.contentsOfDirectory(atPath: url.path)
        if remaining.isEmpty {
            try fileManager.removeItem(at: url)
        }
    }
}
