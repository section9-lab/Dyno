import AppKit
import Combine
import Foundation

struct SandboxBookmarkEntry: Codable, Identifiable, Hashable {
    let id: UUID
    var path: String
    var bookmarkData: Data

    init(id: UUID = UUID(), path: String, bookmarkData: Data) {
        self.id = id
        self.path = path
        self.bookmarkData = bookmarkData
    }
}

enum SandboxAuthorizationStatus: String {
    case active
    case stale
    case invalid
}

@MainActor
final class SandboxAccessManager: ObservableObject {
    static let shared = SandboxAccessManager()

    @Published private(set) var entries: [SandboxBookmarkEntry] = []
    @Published private(set) var authorizedRoots: [URL] = []
    @Published private(set) var statuses: [UUID: SandboxAuthorizationStatus] = [:]

    private static let storageKey = "agent.sandbox.bookmarks.v1"
    private var activeByPath: [String: URL] = [:]

    private init() {
        load()
        resolveAndActivateBookmarks()
    }

    func authorizeDirectoryViaOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = L10n.tr("settings.files.authorize")
        panel.message = L10n.tr("settings.files.authorize_panel_message")

        guard panel.runModal() == .OK, let url = panel.url else { return }
        addAuthorizedDirectory(url)
    }

    func addAuthorizedDirectory(_ url: URL) {
        let normalizedPath = url.standardizedFileURL.path

        if entries.contains(where: { $0.path == normalizedPath }) {
            resolveAndActivateBookmarks()
            return
        }

        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            entries.append(SandboxBookmarkEntry(path: normalizedPath, bookmarkData: bookmark))
            save()
            resolveAndActivateBookmarks()
        } catch {
            AppLog.sandbox.error("Failed to create sandbox bookmark for \(normalizedPath, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    func removeEntry(_ entry: SandboxBookmarkEntry) {
        if let active = activeByPath[entry.path] {
            active.stopAccessingSecurityScopedResource()
        }
        activeByPath.removeValue(forKey: entry.path)
        entries.removeAll { $0.id == entry.id }
        statuses.removeValue(forKey: entry.id)
        save()
        resolveAndActivateBookmarks()
    }

    func reauthorizeEntry(_ entry: SandboxBookmarkEntry) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = L10n.tr("settings.files.reauthorize")
        panel.message = L10n.tr("settings.files.reauthorize_panel_message")

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
            entries[idx].path = url.standardizedFileURL.path
            entries[idx].bookmarkData = bookmark
            save()
            resolveAndActivateBookmarks()
        } catch {
            AppLog.sandbox.error("Failed to refresh bookmark: \(error.localizedDescription, privacy: .public)")
        }
    }

    func refreshAccess() {
        resolveAndActivateBookmarks()
    }

    func status(of entry: SandboxBookmarkEntry) -> SandboxAuthorizationStatus {
        statuses[entry.id] ?? .invalid
    }

    private func resolveAndActivateBookmarks() {
        for (_, url) in activeByPath {
            url.stopAccessingSecurityScopedResource()
        }
        activeByPath.removeAll()

        var activeRoots: [URL] = []
        var updatedEntries: [SandboxBookmarkEntry] = []
        var updatedStatuses: [UUID: SandboxAuthorizationStatus] = [:]

        for var entry in entries {
            do {
                var isStale = false
                let url = try URL(
                    resolvingBookmarkData: entry.bookmarkData,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )

                let started = url.startAccessingSecurityScopedResource()
                if started {
                    activeByPath[entry.path] = url
                    activeRoots.append(url)
                }

                if isStale {
                    let refreshed = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                    entry.bookmarkData = refreshed
                }

                updatedEntries.append(entry)

                if !started {
                    updatedStatuses[entry.id] = .invalid
                } else if isStale {
                    updatedStatuses[entry.id] = .stale
                } else {
                    updatedStatuses[entry.id] = .active
                }
            } catch {
                updatedStatuses[entry.id] = .invalid
                updatedEntries.append(entry)
                AppLog.sandbox.error("Failed to resolve bookmark for \(entry.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        entries = updatedEntries
        authorizedRoots = activeRoots
        statuses = updatedStatuses
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([SandboxBookmarkEntry].self, from: data)
        else {
            entries = []
            return
        }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
