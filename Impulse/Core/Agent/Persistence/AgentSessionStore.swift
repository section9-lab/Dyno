import Foundation

protocol AgentSessionStoring {
    func load(workspace: String) throws -> [SessionConversationSnapshot]
    func save(conversations: [SessionConversationSnapshot], workspace: String) throws
}

final class AgentSessionStore: AgentSessionStoring {
    private let formatter = ISO8601DateFormatter()

    func load(workspace: String) throws -> [SessionConversationSnapshot] {
        let sessionDir = sessionDirectory(for: workspace)
        guard FileManager.default.fileExists(atPath: sessionDir.path) else { return [] }

        let files = try FileManager.default.contentsOfDirectory(at: sessionDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var snapshots: [SessionConversationSnapshot] = []

        for file in files {
            let content = try String(contentsOf: file, encoding: .utf8)
            let lines = content.split(separator: "\n", omittingEmptySubsequences: true)

            var conversationID = file.deletingPathExtension().lastPathComponent
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
                        conversationID = id
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
                    let firstKeptEntryID = root["firstKeptEntryId"] as? String
                    latestCompaction = (summary: summary, timestamp: ts, firstKeptEntryID: firstKeptEntryID)
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

            var messages = parsedMessages.map { $0.snapshot }
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
                    let keptMessages = parsedMessages[firstKeptIndex...].map { $0.snapshot }
                    messages = [summarySnapshot] + keptMessages
                } else {
                    messages = [summarySnapshot] + messages
                }
            }

            guard !messages.isEmpty else { continue }
            let titleSource = messages.first(where: { $0.role == "user" })?.content ?? messages[0].content
            let title = titleSource.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)

            snapshots.append(
                SessionConversationSnapshot(
                    id: conversationID,
                    title: title.isEmpty ? "(empty)" : title,
                    startedAt: startedAt,
                    messages: messages
                )
            )
        }

        return snapshots.sorted { $0.startedAt > $1.startedAt }
    }

    func save(conversations: [SessionConversationSnapshot], workspace: String) throws {
        let sessionDir = sessionDirectory(for: workspace)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)

        var currentFileNames = Set<String>()

        for conversation in conversations {
            let stamp = Int(conversation.startedAt.timeIntervalSince1970 * 1000)
            let fileName = "\(stamp)_\(conversation.id).jsonl"
            let url = sessionDir.appendingPathComponent(fileName)
            currentFileNames.insert(fileName)
            try write(conversation: conversation, to: url, workspace: workspace)
        }

        let existing = try FileManager.default.contentsOfDirectory(at: sessionDir, includingPropertiesForKeys: nil)
        for file in existing where file.pathExtension == "jsonl" {
            if !currentFileNames.contains(file.lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    private func write(conversation: SessionConversationSnapshot, to url: URL, workspace: String) throws {
        var lines: [String] = []

        let header: [String: Any] = [
            "type": "session",
            "version": 3,
            "id": conversation.id,
            "timestamp": formatter.string(from: conversation.startedAt),
            "cwd": workspace,
        ]
        lines.append(jsonLine(header))

        var parentID: String? = nil
        let entryIDs = conversation.messages.enumerated().map { String(format: "%08x", $0.offset + 1) }
        var cumulativeReadFiles = Set<String>()
        var cumulativeModifiedFiles = Set<String>()

        for (index, message) in conversation.messages.enumerated() {
            let entryID = entryIDs[index]
            mergeFileOps(from: message, readFiles: &cumulativeReadFiles, modifiedFiles: &cumulativeModifiedFiles)

            if message.kind == "compaction_summary" {
                var entry: [String: Any] = [
                    "type": "compaction",
                    "id": entryID,
                    "parentId": parentID as Any,
                    "timestamp": Int(message.timestamp.timeIntervalSince1970 * 1000),
                    "summary": message.content,
                    "tokensBefore": estimateTokens(in: Array(conversation.messages.prefix(index))),
                    "details": [
                        "readFiles": cumulativeReadFiles.sorted(),
                        "modifiedFiles": cumulativeModifiedFiles.sorted(),
                    ],
                ]

                if let firstKeptEntryID = firstKeptEntryID(forCompactionAt: index, in: conversation.messages, entryIDs: entryIDs) {
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

        for next in (index + 1)..<messages.count {
            if messages[next].kind != "compaction_summary" {
                return entryIDs[next]
            }
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

    private func sessionDirectory(for workspace: String) -> URL {
        URL(fileURLWithPath: workspace).agentSessionDirectory()
    }
}
