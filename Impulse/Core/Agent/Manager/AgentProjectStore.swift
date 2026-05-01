import Foundation

/// Persists the lightweight `ProjectSnapshot` index (project paths,
/// session titles, kanban tasks). Wraps `AgentSessionStoring` and centralises
/// the on-disk path.
struct AgentProjectStore {
    private let storage: AgentSessionStoring
    private let storageDirectoryPath: String

    init(
        storage: AgentSessionStoring = AgentSessionStore(),
        storageDirectoryPath: String = AgentServiceConfig.defaultAppDataDirectoryPath
    ) {
        self.storage = storage
        self.storageDirectoryPath = storageDirectoryPath
    }

    func loadProjects() -> [ProjectSnapshot] {
        do {
            return try storage.loadProjects(storageDirectory: storageDirectoryPath)
        } catch {
            AppLog.persistence.error("Failed to load persisted projects: \(error.localizedDescription, privacy: .public)")
            Task { @MainActor in
                UserAlertCenter.shared.post(
                    .persistenceError(
                        id: "projects.load.failed",
                        title: L10n.tr("alert.projects_load_failed.title"),
                        detail: L10n.tr("alert.projects_load_failed.detail")
                    )
                )
            }
            return []
        }
    }

    func saveProjects(_ projects: [ProjectSnapshot]) {
        do {
            try storage.saveProjects(projects, storageDirectory: storageDirectoryPath)
        } catch {
            AppLog.persistence.error("Failed to persist project snapshots: \(error.localizedDescription, privacy: .public)")
            Task { @MainActor in
                UserAlertCenter.shared.post(
                    .persistenceError(
                        id: "projects.save.failed",
                        title: L10n.tr("alert.projects_save_failed.title"),
                        detail: L10n.tr("alert.projects_save_failed.detail")
                    )
                )
            }
        }
    }
}
