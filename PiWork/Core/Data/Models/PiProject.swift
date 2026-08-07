import Foundation

/// A user-linked project folder — the working directory a `pi` agent
/// subprocess runs in for that project's sessions/tasks.
struct PiProject: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var path: String
    var createdAt: Date

    init(id: UUID = UUID(), name: String, path: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.path = path
        self.createdAt = createdAt
    }

    var folderURL: URL { URL(fileURLWithPath: path, isDirectory: true) }
}

/// Persists linked project folders as a small JSON file in Application
/// Support. Deliberately simple (no Core Data) for this initial rewrite —
/// the data volume here is tiny (a user's list of project folders), and it
/// keeps the bootstrap unblocked by tooling (see AGENTS.md for why
/// `xcodegen`/Xcode-project generation, not Core Data modeling, was this
/// rewrite's first hard problem to solve).
@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [PiProject] = []

    private let storeURL: URL

    init(storeURL: URL? = nil) {
        if let storeURL {
            self.storeURL = storeURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("pi-work", isDirectory: true)
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            self.storeURL = support.appendingPathComponent("projects.json")
        }
        load()
    }

    func addProject(path: String, name: String? = nil) {
        let resolvedName = name ?? URL(fileURLWithPath: path).lastPathComponent
        guard !projects.contains(where: { $0.path == path }) else { return }
        projects.append(PiProject(name: resolvedName, path: path))
        save()
    }

    func removeProject(_ project: PiProject) {
        projects.removeAll { $0.id == project.id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL) else { return }
        projects = (try? JSONDecoder().decode([PiProject].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
