import Foundation
import SwiftData

struct ChatHistoryService {
    private let supportedKinds: Set<String> = Set(ItemKind.allCases.map(\.rawValue))

    func buildProjects(from items: [Item], persistedProjects: [ProjectSnapshot]) -> [ChatProject] {
        let sortedItems = items
            .filter { supportedKinds.contains($0.kind) }
            .sorted { $0.timestamp < $1.timestamp }

        var groupedByProject: [String: [String: [Item]]] = [:]
        for item in sortedItems {
            guard !item.projectPath.isEmpty, !item.conversationID.isEmpty else { continue }
            groupedByProject[item.projectPath, default: [:]][item.conversationID, default: []].append(item)
        }

        let persistedByPath = Dictionary(uniqueKeysWithValues: persistedProjects.map { ($0.path, $0) })
        let orderedPaths = Array(Set(persistedProjects.map(\.path)).union(groupedByProject.keys)).sorted { lhs, rhs in
            let lhsDate = persistedByPath[lhs]?.addedAt ?? groupedByProject[lhs]?.values.flatMap { $0 }.map(\.timestamp).min() ?? .distantPast
            let rhsDate = persistedByPath[rhs]?.addedAt ?? groupedByProject[rhs]?.values.flatMap { $0 }.map(\.timestamp).min() ?? .distantPast
            return lhsDate > rhsDate
        }

        return orderedPaths.map { projectPath in
            let persisted = persistedByPath[projectPath]
            let groupedSessions = groupedByProject[projectPath] ?? [:]
            let sessionIDs = Array(Set((persisted?.sessions.map(\.id) ?? []) + groupedSessions.keys))

            let sessions = sessionIDs.compactMap { sessionID -> ChatSession? in
                let messages = (groupedSessions[sessionID] ?? []).sorted { $0.timestamp < $1.timestamp }
                let snapshot = persisted?.sessions.first(where: { $0.id == sessionID })

                if let snapshot {
                    return ChatSession(
                        id: snapshot.id,
                        projectPath: projectPath,
                        title: normalizedTitle(from: snapshot.title),
                        startedAt: snapshot.startedAt,
                        messages: messages
                    )
                }

                guard let first = messages.first else { return nil }
                let titleSource = messages.first(where: { $0.isUser })?.content ?? first.content
                return ChatSession(
                    id: sessionID,
                    projectPath: projectPath,
                    title: normalizedTitle(from: titleSource),
                    startedAt: first.timestamp,
                    messages: messages
                )
            }
            .sorted { $0.startedAt > $1.startedAt }

            return ChatProject(
                id: projectPath,
                path: projectPath,
                name: URL(fileURLWithPath: projectPath).lastPathComponent.isEmpty ? projectPath : URL(fileURLWithPath: projectPath).lastPathComponent,
                sessions: sessions,
                kanbanTasks: persisted?.kanbanTasks ?? []
            )
        }
    }

    func selectedProject(selectedPath: String?, projects: [ChatProject]) -> ChatProject? {
        guard let selectedPath else { return nil }
        return projects.first(where: { $0.path == selectedPath })
    }

    func selectedSession(
        selectedProjectPath: String?,
        selectedSessionID: String?,
        projects: [ChatProject]
    ) -> ChatSession? {
        guard let project = selectedProject(selectedPath: selectedProjectPath, projects: projects),
              let selectedSessionID
        else {
            return nil
        }
        return project.sessions.first(where: { $0.id == selectedSessionID })
    }

    func displayedItems(
        selectedProjectPath: String?,
        selectedSessionID: String?,
        projects: [ChatProject]
    ) -> [Item] {
        selectedSession(
            selectedProjectPath: selectedProjectPath,
            selectedSessionID: selectedSessionID,
            projects: projects
        )?.messages ?? []
    }

    func addProject(path: String, existingProjects: [ProjectSnapshot]) -> [ProjectSnapshot] {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return existingProjects }
        guard !existingProjects.contains(where: { $0.path == path }) else { return existingProjects }

        var projects = existingProjects
        projects.append(ProjectSnapshot(id: projectKey(for: path), path: path, addedAt: Date(), sessions: [], kanbanTasks: []))
        return projects.sorted { $0.addedAt > $1.addedAt }
    }

    func removeProject(path: String, persistedProjects: [ProjectSnapshot], modelContext: ModelContext) -> [ProjectSnapshot] {
        // Delete all StoredSessions belonging to this project; cascade rules
        // remove their messages / tool runs / compaction summaries.
        let descriptor = FetchDescriptor<StoredSession>(
            predicate: #Predicate { $0.projectPath == path }
        )
        if let sessions = try? modelContext.fetch(descriptor) {
            for session in sessions {
                modelContext.delete(session)
            }
        }
        return persistedProjects.filter { $0.path != path }
    }

    func createSession(in projectPath: String, persistedProjects: [ProjectSnapshot]) -> (projects: [ProjectSnapshot], sessionID: String)? {
        guard let projectIndex = persistedProjects.firstIndex(where: { $0.path == projectPath }) else { return nil }

        var updatedProjects = persistedProjects
        let sessionID = UUID().uuidString
        let session = ProjectSessionSnapshot(
            id: sessionID,
            projectPath: projectPath,
            title: "New Session",
            startedAt: Date(),
            messages: []
        )
        var project = updatedProjects[projectIndex]
        project = ProjectSnapshot(
            id: project.id,
            path: project.path,
            addedAt: project.addedAt,
            sessions: [session] + project.sessions,
            kanbanTasks: project.kanbanTasks
        )
        updatedProjects[projectIndex] = project
        return (updatedProjects, sessionID)
    }

    @discardableResult
    func renameSession(
        projectPath: String,
        sessionID: String,
        newTitle: String,
        items: [Item],
        persistedProjects: inout [ProjectSnapshot],
        modelContext: ModelContext
    ) -> Bool {
        let normalized = normalizedTitle(from: newTitle)
        guard normalized != "(empty)" else { return false }

        // Update the StoredMessage so the new name shows up the next time the
        // transcript is re-projected (Items are read-only value types now;
        // mutation has to flow through the SwiftData entity).
        let descriptor = FetchDescriptor<StoredSession>(
            predicate: #Predicate { $0.id == sessionID }
        )
        if let session = (try? modelContext.fetch(descriptor))?.first {
            session.title = normalized
            // Also rewrite the first user message if present, so the
            // existing UI behaviour (rename = edit first user prompt) carries
            // over and downstream prelude builders see the new title.
            if let firstUser = session.messages
                .filter({ $0.role == "user" })
                .sorted(by: { $0.timestamp < $1.timestamp })
                .first {
                firstUser.content = normalized
            }
        }

        guard let projectIndex = persistedProjects.firstIndex(where: { $0.path == projectPath }),
              let sessionIndex = persistedProjects[projectIndex].sessions.firstIndex(where: { $0.id == sessionID })
        else {
            return false
        }

        var project = persistedProjects[projectIndex]
        var session = project.sessions[sessionIndex]
        session = ProjectSessionSnapshot(
            id: session.id,
            projectPath: session.projectPath,
            title: normalized,
            startedAt: session.startedAt,
            messages: session.messages
        )
        var sessions = project.sessions
        sessions[sessionIndex] = session
        project = ProjectSnapshot(
            id: project.id,
            path: project.path,
            addedAt: project.addedAt,
            sessions: sessions,
            kanbanTasks: project.kanbanTasks
        )
        persistedProjects[projectIndex] = project
        return true
    }

    func deleteSession(
        projectPath: String,
        sessionID: String,
        persistedProjects: inout [ProjectSnapshot],
        modelContext: ModelContext
    ) {
        // Delete the StoredSession; cascade rules clear messages/toolRuns/summaries.
        let descriptor = FetchDescriptor<StoredSession>(
            predicate: #Predicate { $0.id == sessionID }
        )
        if let sessions = try? modelContext.fetch(descriptor) {
            for session in sessions {
                modelContext.delete(session)
            }
        }

        guard let projectIndex = persistedProjects.firstIndex(where: { $0.path == projectPath }) else { return }
        let project = persistedProjects[projectIndex]
        let sessions = project.sessions.filter { $0.id != sessionID }
        let filteredTasks = project.kanbanTasks.map { task in
            let linked = task.linkedSessionIDs.filter { $0 != sessionID }
            let primary = task.primarySessionID == sessionID ? linked.first : task.primarySessionID
            return KanbanTaskSnapshot(
                id: task.id,
                projectPath: task.projectPath,
                title: task.title,
                status: task.status,
                priority: task.priority,
                primarySessionID: primary,
                linkedSessionIDs: linked,
                assigneeName: task.assigneeName,
                notes: task.notes,
                createdAt: task.createdAt,
                updatedAt: task.updatedAt
            )
        }
        persistedProjects[projectIndex] = ProjectSnapshot(
            id: project.id,
            path: project.path,
            addedAt: project.addedAt,
            sessions: sessions,
            kanbanTasks: filteredTasks
        )
    }

    func updateSessionSnapshot(
        projectPath: String,
        sessionID: String,
        items: [Item],
        persistedProjects: inout [ProjectSnapshot]
    ) {
        guard let projectIndex = persistedProjects.firstIndex(where: { $0.path == projectPath }) else { return }

        let messages = items
            .filter { $0.projectPath == projectPath && $0.conversationID == sessionID && supportedKinds.contains($0.kind) }
            .sorted { $0.timestamp < $1.timestamp }

        guard let first = messages.first else { return }
        let titleSource = messages.first(where: { $0.isUser })?.content ?? first.content
        let snapshot = ProjectSessionSnapshot(
            id: sessionID,
            projectPath: projectPath,
            title: normalizedTitle(from: titleSource),
            startedAt: first.timestamp,
            messages: messages.map { message in
                SessionMessageSnapshot(
                    role: message.isUser ? "user" : "assistant",
                    content: message.content,
                    timestamp: message.timestamp,
                    kind: message.kind
                )
            }
        )

        var project = persistedProjects[projectIndex]
        var sessions = project.sessions.filter { $0.id != sessionID }
        sessions.insert(snapshot, at: 0)
        sessions.sort { $0.startedAt > $1.startedAt }
        persistedProjects[projectIndex] = ProjectSnapshot(
            id: project.id,
            path: project.path,
            addedAt: project.addedAt,
            sessions: sessions,
            kanbanTasks: project.kanbanTasks
        )
    }

    func kanbanTasks(for projectPath: String, persistedProjects: [ProjectSnapshot]) -> [KanbanTaskSnapshot] {
        persistedProjects.first(where: { $0.path == projectPath })?.kanbanTasks ?? []
    }

    func upsertKanbanTask(
        _ task: KanbanTaskSnapshot,
        persistedProjects: inout [ProjectSnapshot]
    ) {
        guard let projectIndex = persistedProjects.firstIndex(where: { $0.path == task.projectPath }) else { return }
        var project = persistedProjects[projectIndex]
        var tasks = project.kanbanTasks.filter { $0.id != task.id }
        tasks.append(task)
        tasks.sort { lhs, rhs in
            if lhs.status != rhs.status {
                return lhs.status.rawValue < rhs.status.rawValue
            }
            return lhs.updatedAt > rhs.updatedAt
        }
        persistedProjects[projectIndex] = ProjectSnapshot(
            id: project.id,
            path: project.path,
            addedAt: project.addedAt,
            sessions: project.sessions,
            kanbanTasks: tasks
        )
    }

    func deleteKanbanTask(
        id: String,
        projectPath: String,
        persistedProjects: inout [ProjectSnapshot]
    ) {
        guard let projectIndex = persistedProjects.firstIndex(where: { $0.path == projectPath }) else { return }
        var project = persistedProjects[projectIndex]
        let tasks = project.kanbanTasks.filter { $0.id != id }
        persistedProjects[projectIndex] = ProjectSnapshot(
            id: project.id,
            path: project.path,
            addedAt: project.addedAt,
            sessions: project.sessions,
            kanbanTasks: tasks
        )
    }

    func restoreSnapshots(_ projects: [ProjectSnapshot], into modelContext: ModelContext) {
        for project in projects.reversed() {
            for session in project.sessions.reversed() {
                let storedSession = StoredSession(
                    id: session.id,
                    projectPath: project.path,
                    title: session.title,
                    startedAt: session.startedAt
                )
                modelContext.insert(storedSession)

                for message in session.messages where supportedKinds.contains(message.kind) {
                    let kind = ItemKind(rawValue: message.kind) ?? .assistantMessage
                    switch kind {
                    case .userMessage:
                        let m = StoredMessage(
                            timestamp: message.timestamp,
                            role: "user",
                            content: message.content,
                            session: storedSession
                        )
                        modelContext.insert(m)
                    case .assistantMessage:
                        let m = StoredMessage(
                            timestamp: message.timestamp,
                            role: "assistant",
                            content: message.content,
                            session: storedSession
                        )
                        modelContext.insert(m)
                    case .compactionSummary:
                        let s = StoredCompactionSummary(
                            timestamp: message.timestamp,
                            content: message.content,
                            session: storedSession
                        )
                        modelContext.insert(s)
                    case .toolExecution:
                        // Tool runs are not currently round-tripped through
                        // ProjectSnapshot JSON — they only live in SwiftData.
                        // (See AgentSessionStore for the JSON shape.)
                        // Skip silently: snapshot has no toolName/status info.
                        continue
                    }
                }
            }
        }
    }

    func projectKey(for path: String) -> String {
        let data = Data(path.utf8)
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        return encoded
    }

    private func normalizedTitle(from raw: String) -> String {
        let singleLine = raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return singleLine.isEmpty ? "(empty)" : singleLine
    }
}
