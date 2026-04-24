import Foundation

protocol AgentSessionStoring {
    func loadProjects(storageDirectory: String) throws -> [ProjectSnapshot]
    func saveProjects(_ projects: [ProjectSnapshot], storageDirectory: String) throws
}

final class AgentSessionStore: AgentSessionStoring {
    private let formatter = ISO8601DateFormatter()
    private let fileManager = FileManager.default

    func loadProjects(storageDirectory: String) throws -> [ProjectSnapshot] {
        let projectsDirectory = projectsDirectory(for: storageDirectory)
        guard fileManager.fileExists(atPath: projectsDirectory.path) else { return [] }

        let projectDirectories = try fileManager.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        }

        return try projectDirectories.compactMap(loadProjectSnapshot(at:)).sorted {
            $0.addedAt > $1.addedAt
        }
    }

    func saveProjects(_ projects: [ProjectSnapshot], storageDirectory: String) throws {
        let projectsDirectory = projectsDirectory(for: storageDirectory)
        try fileManager.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)

        let currentProjectKeys = Set(projects.map(\.id))
        let existingDirectories = try fileManager.contentsOfDirectory(
            at: projectsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for project in projects {
            try saveProject(project, under: projectsDirectory)
        }

        for directory in existingDirectories {
            let key = directory.lastPathComponent
            if !currentProjectKeys.contains(key) {
                try? fileManager.removeItem(at: directory)
            }
        }
    }

    private func saveProject(_ project: ProjectSnapshot, under projectsDirectory: URL) throws {
        let projectDirectory = projectsDirectory.appendingPathComponent(project.id, isDirectory: true)
        let sessionsDirectory = projectDirectory.appendingPathComponent("sessions", isDirectory: true)
        try fileManager.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

        let metadata: [String: Any] = [
            "id": project.id,
            "path": project.path,
            "addedAt": formatter.string(from: project.addedAt),
        ]
        let metadataURL = projectDirectory.appendingPathComponent("project.json")
        let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try metadataData.write(to: metadataURL, options: .atomic)

        let kanbanURL = projectDirectory.appendingPathComponent("kanban.json")
        let kanbanData = try JSONEncoder().encode(project.kanbanTasks)
        try kanbanData.write(to: kanbanURL, options: .atomic)

        var currentSessionFileNames = Set<String>()
        for session in project.sessions {
            let stamp = Int(session.startedAt.timeIntervalSince1970 * 1000)
            let fileName = "\(stamp)_\(session.id).jsonl"
            currentSessionFileNames.insert(fileName)
            let sessionURL = sessionsDirectory.appendingPathComponent(fileName)
            try write(session: session, to: sessionURL)
        }

        let existingFiles = try fileManager.contentsOfDirectory(at: sessionsDirectory, includingPropertiesForKeys: nil)
        for file in existingFiles where file.pathExtension == "jsonl" {
            if !currentSessionFileNames.contains(file.lastPathComponent) {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    private func loadProjectSnapshot(at directory: URL) throws -> ProjectSnapshot? {
        let metadataURL = directory.appendingPathComponent("project.json")
        guard fileManager.fileExists(atPath: metadataURL.path) else { return nil }

        let metadataData = try Data(contentsOf: metadataURL)
        guard let metadata = try JSONSerialization.jsonObject(with: metadataData) as? [String: Any],
              let id = metadata["id"] as? String,
              let path = metadata["path"] as? String
        else {
            return nil
        }

        let addedAtString = metadata["addedAt"] as? String
        let addedAt = addedAtString.flatMap(formatter.date(from:)) ?? Date()

        let sessionsDirectory = directory.appendingPathComponent("sessions", isDirectory: true)
        let sessionFiles = (try? fileManager.contentsOfDirectory(at: sessionsDirectory, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []

        let sessions = try sessionFiles.compactMap { try loadSessionSnapshot(from: $0, projectPath: path) }
            .sorted { $0.startedAt > $1.startedAt }

        let kanbanURL = directory.appendingPathComponent("kanban.json")
        let kanbanTasks: [KanbanTaskSnapshot]
        if fileManager.fileExists(atPath: kanbanURL.path) {
            let kanbanData = try Data(contentsOf: kanbanURL)
            kanbanTasks = (try? JSONDecoder().decode([KanbanTaskSnapshot].self, from: kanbanData)) ?? []
        } else {
            kanbanTasks = []
        }

        return ProjectSnapshot(id: id, path: path, addedAt: addedAt, sessions: sessions, kanbanTasks: kanbanTasks)
    }

    private func loadSessionSnapshot(from file: URL, projectPath: String) throws -> ProjectSessionSnapshot? {
        let content = try String(contentsOf: file, encoding: .utf8)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)

        var sessionID = file.deletingPathExtension().lastPathComponent
        var startedAt = Date()
        var parsedMessages: [(id: String, snapshot: SessionMessageSnapshot)] = []
        var latestCompaction: (summary: String, timestamp: Date, firstKeptEntryID: String?)?

        for line in lines {
            guard let data = line.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = root["type"] as? String
            else {
                continue
            }

            if type == "session" {
                if let id = root["id"] as? String, !id.isEmpty {
                    sessionID = id
                }
                if let stamp = root["timestamp"] as? String, let date = formatter.date(from: stamp) {
                    startedAt = date
                }
                continue
            }

            if type == "compaction" {
                guard let summary = root["summary"] as? String else { continue }
                let tsMs = (root["timestamp"] as? Double)
                    ?? (root["timestamp"] as? Int).map(Double.init)
                    ?? startedAt.timeIntervalSince1970 * 1000
                let ts = Date(timeIntervalSince1970: tsMs / 1000)
                latestCompaction = (summary: summary, timestamp: ts, firstKeptEntryID: root["firstKeptEntryId"] as? String)
                continue
            }

            guard type == "message",
                  let message = root["message"] as? [String: Any],
                  let role = message["role"] as? String
            else {
                continue
            }

            let text: String
            if let direct = message["content"] as? String {
                text = direct
            } else if let blocks = message["content"] as? [[String: Any]] {
                text = blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
            } else {
                text = ""
            }

            guard !text.isEmpty else { continue }

            let tsMs = (message["timestamp"] as? Double)
                ?? (message["timestamp"] as? Int).map(Double.init)
                ?? startedAt.timeIntervalSince1970 * 1000
            let ts = Date(timeIntervalSince1970: tsMs / 1000)
            let kind = (message["impulseKind"] as? String)
                ?? (role == "user" ? "user_message" : "assistant_message")
            let entryID = (root["id"] as? String) ?? UUID().uuidString

            parsedMessages.append((
                id: entryID,
                snapshot: SessionMessageSnapshot(role: role, content: text, timestamp: ts, kind: kind)
            ))
        }

        var messages = parsedMessages.map(\.snapshot)
        if let latestCompaction {
            let summarySnapshot = SessionMessageSnapshot(
                role: "assistant",
                content: latestCompaction.summary,
                timestamp: latestCompaction.timestamp,
                kind: "compaction_summary"
            )

            if let firstKeptEntryID = latestCompaction.firstKeptEntryID,
               let firstKeptIndex = parsedMessages.firstIndex(where: { $0.id == firstKeptEntryID })
            {
                let keptMessages = parsedMessages[firstKeptIndex...].map(\.snapshot)
                messages = [summarySnapshot] + keptMessages
            } else {
                messages = [summarySnapshot] + messages
            }
        }

        guard !messages.isEmpty else { return nil }
        let titleSource = messages.first(where: { $0.role == "user" })?.content ?? messages[0].content
        let title = normalizedTitle(from: titleSource)

        return ProjectSessionSnapshot(
            id: sessionID,
            projectPath: projectPath,
            title: title,
            startedAt: startedAt,
            messages: messages
        )
    }

    private func write(session: ProjectSessionSnapshot, to url: URL) throws {
        var lines: [String] = []
        let header: [String: Any] = [
            "type": "session",
            "version": 4,
            "id": session.id,
            "projectPath": session.projectPath,
            "timestamp": formatter.string(from: session.startedAt),
            "cwd": session.projectPath,
        ]
        lines.append(jsonLine(header))

        var parentID: String? = nil
        let entryIDs = session.messages.enumerated().map { String(format: "%08x", $0.offset + 1) }
        var cumulativeReadFiles = Set<String>()
        var cumulativeModifiedFiles = Set<String>()

        for (index, message) in session.messages.enumerated() {
            let entryID = entryIDs[index]
            mergeFileOps(from: message, readFiles: &cumulativeReadFiles, modifiedFiles: &cumulativeModifiedFiles)

            if message.kind == "compaction_summary" {
                var entry: [String: Any] = [
                    "type": "compaction",
                    "id": entryID,
                    "parentId": parentID as Any,
                    "timestamp": Int(message.timestamp.timeIntervalSince1970 * 1000),
                    "summary": message.content,
                    "tokensBefore": estimateTokens(in: Array(session.messages.prefix(index))),
                    "details": [
                        "readFiles": cumulativeReadFiles.sorted(),
                        "modifiedFiles": cumulativeModifiedFiles.sorted(),
                    ],
                ]

                if let firstKeptEntryID = firstKeptEntryID(forCompactionAt: index, in: session.messages, entryIDs: entryIDs) {
                    entry["firstKeptEntryId"] = firstKeptEntryID
                }

                lines.append(jsonLine(entry))
                parentID = entryID
                continue
            }

            let messageObject: [String: Any] = [
                "role": message.role,
                "content": message.content,
                "timestamp": Int(message.timestamp.timeIntervalSince1970 * 1000),
                "impulseKind": message.kind,
            ]

            var entry: [String: Any] = [
                "type": "message",
                "id": entryID,
                "timestamp": formatter.string(from: message.timestamp),
                "message": messageObject,
            ]
            entry["parentId"] = parentID as Any
            lines.append(jsonLine(entry))
            parentID = entryID
        }

        try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func firstKeptEntryID(
        forCompactionAt index: Int,
        in messages: [SessionMessageSnapshot],
        entryIDs: [String]
    ) -> String? {
        guard index < messages.count else { return nil }

        for next in (index + 1)..<messages.count where messages[next].kind != "compaction_summary" {
            return entryIDs[next]
        }

        return nil
    }

    private func estimateTokens(in messages: [SessionMessageSnapshot]) -> Int {
        messages.reduce(0) { partial, message in
            partial + max(1, message.content.count / 4) + 12
        }
    }

    private func mergeFileOps(
        from message: SessionMessageSnapshot,
        readFiles: inout Set<String>,
        modifiedFiles: inout Set<String>
    ) {
        guard message.kind == "tool_execution",
              let data = message.content.data(using: .utf8),
              let payload = try? JSONDecoder().decode(PersistedToolExecution.self, from: data)
        else {
            return
        }

        guard let path = filePath(fromSummary: payload.summary), !path.isEmpty else { return }

        switch payload.toolName {
        case "read":
            readFiles.insert(path)
        case "write", "edit":
            modifiedFiles.insert(path)
        default:
            break
        }
    }

    private func filePath(fromSummary summary: String) -> String? {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let range = trimmed.range(of: " (") {
            return String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    private func jsonLine(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private func normalizedTitle(from raw: String) -> String {
        let singleLine = raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return singleLine.isEmpty ? "(empty)" : singleLine
    }

    private func projectsDirectory(for storageDirectory: String) -> URL {
        URL(fileURLWithPath: storageDirectory).appendingPathComponent("projects", isDirectory: true)
    }
}
