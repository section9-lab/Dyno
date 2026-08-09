import Foundation

enum ScheduleRecurrence: String, CaseIterable, Codable, Identifiable {
    case daily
    case weekdays
    case weekly

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .daily: return "schedule.recurrence.daily"
        case .weekdays: return "schedule.recurrence.weekdays"
        case .weekly: return "schedule.recurrence.weekly"
        }
    }
}

enum ScheduleSortOrder: String, CaseIterable, Identifiable {
    case newest
    case name
    case time

    var id: String { rawValue }

    func apply(
        to tasks: [ScheduledTask],
        calendar: Calendar = .current
    ) -> [ScheduledTask] {
        tasks.sorted { lhs, rhs in
            switch self {
            case .newest:
                return lhs.createdAt > rhs.createdAt
            case .name:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .time:
                let leftMinutes = calendar.component(.hour, from: lhs.time) * 60
                    + calendar.component(.minute, from: lhs.time)
                let rightMinutes = calendar.component(.hour, from: rhs.time) * 60
                    + calendar.component(.minute, from: rhs.time)
                if leftMinutes == rightMinutes {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return leftMinutes < rightMinutes
            }
        }
    }
}

struct ScheduledTask: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var instruction: String
    var recurrence: ScheduleRecurrence
    var time: Date
    var weekday: Int?
    var projectPath: String?
    var accessMode: AgentHostAccessMode?
    var isEnabled: Bool
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        name: String,
        instruction: String,
        recurrence: ScheduleRecurrence,
        time: Date,
        weekday: Int? = nil,
        projectPath: String?,
        accessMode: AgentHostAccessMode? = nil,
        isEnabled: Bool,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.instruction = instruction
        self.recurrence = recurrence
        self.time = time
        self.weekday = weekday
        self.projectPath = projectPath
        self.accessMode = accessMode
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var unattendedAccessMode: AgentHostAccessMode {
        accessMode == .full ? .full : .readOnly
    }
}

struct ScheduleDraft: Equatable {
    var id: UUID?
    var name: String
    var instruction: String
    var recurrence: ScheduleRecurrence
    var time: Date
    var weekday: Int?
    var projectPath: String?
    var accessMode: AgentHostAccessMode

    init(
        id: UUID? = nil,
        name: String = "",
        instruction: String = "",
        recurrence: ScheduleRecurrence = .daily,
        time: Date = Date(),
        weekday: Int? = nil,
        projectPath: String? = nil,
        accessMode: AgentHostAccessMode = .readOnly
    ) {
        self.id = id
        self.name = name
        self.instruction = instruction
        self.recurrence = recurrence
        self.time = time
        self.weekday = weekday
        self.projectPath = projectPath
        self.accessMode = accessMode
    }

    init(task: ScheduledTask) {
        id = task.id
        name = task.name
        instruction = task.instruction
        recurrence = task.recurrence
        time = task.time
        weekday = task.weekday
        projectPath = task.projectPath
        accessMode = task.unattendedAccessMode
    }
}

enum ScheduleValidationError: Error, Equatable {
    case nameRequired
    case instructionRequired
}

enum ScheduleRunStatus: String, Codable, Equatable {
    case running
    case completed
    case failed
}

struct ScheduleRunRecord: Codable, Equatable, Identifiable {
    let id: UUID
    let taskID: UUID
    let taskName: String
    let startedAt: Date
    var scheduledAt: Date?
    var finishedAt: Date?
    var sessionID: String?
    var errorMessage: String?
    var status: ScheduleRunStatus
}

private struct ScheduleSnapshot: Codable {
    var tasks: [ScheduledTask]
    var records: [ScheduleRunRecord]
}

@MainActor
final class ScheduleStore: ObservableObject {
    @Published private(set) var tasks: [ScheduledTask] = []
    @Published private(set) var records: [ScheduleRunRecord] = []

    private let storeURL: URL

    init(storeURL: URL? = nil) {
        if let storeURL {
            self.storeURL = storeURL
        } else {
            let support = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0].appendingPathComponent("pi-work", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: support,
                withIntermediateDirectories: true
            )
            self.storeURL = support.appendingPathComponent("schedules.json")
        }
        load()
    }

    @discardableResult
    func save(_ draft: ScheduleDraft) throws -> ScheduledTask {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ScheduleValidationError.nameRequired }

        let instruction = draft.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else {
            throw ScheduleValidationError.instructionRequired
        }

        let now = Date()
        let task: ScheduledTask
        if let id = draft.id, let index = tasks.firstIndex(where: { $0.id == id }) {
            let existing = tasks[index]
            task = ScheduledTask(
                id: existing.id,
                name: name,
                instruction: instruction,
                recurrence: draft.recurrence,
                time: draft.time,
                weekday: normalizedWeekday(for: draft),
                projectPath: draft.projectPath,
                accessMode: normalizedAccessMode(draft.accessMode),
                isEnabled: existing.isEnabled,
                createdAt: existing.createdAt,
                updatedAt: now
            )
            tasks[index] = task
        } else {
            task = ScheduledTask(
                id: draft.id ?? UUID(),
                name: name,
                instruction: instruction,
                recurrence: draft.recurrence,
                time: draft.time,
                weekday: normalizedWeekday(for: draft),
                projectPath: draft.projectPath,
                accessMode: normalizedAccessMode(draft.accessMode),
                isEnabled: true,
                createdAt: now,
                updatedAt: now
            )
            tasks.append(task)
        }
        persist()
        return task
    }

    func setEnabled(_ isEnabled: Bool, for taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].isEnabled = isEnabled
        tasks[index].updatedAt = Date()
        persist()
    }

    @discardableResult
    func beginRun(
        for taskID: UUID,
        scheduledAt: Date? = nil,
        at date: Date = Date()
    ) -> ScheduleRunRecord? {
        guard let task = tasks.first(where: { $0.id == taskID }) else { return nil }
        let record = ScheduleRunRecord(
            id: UUID(),
            taskID: task.id,
            taskName: task.name,
            startedAt: date,
            scheduledAt: scheduledAt,
            finishedAt: nil,
            sessionID: nil,
            errorMessage: nil,
            status: .running
        )
        records.insert(record, at: 0)
        persist()
        return record
    }

    func completeRun(
        _ recordID: UUID,
        sessionID: String,
        at date: Date = Date()
    ) {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
        records[index].status = .completed
        records[index].sessionID = sessionID
        records[index].finishedAt = date
        records[index].errorMessage = nil
        persist()
    }

    func failRun(
        _ recordID: UUID,
        sessionID: String? = nil,
        message: String,
        at date: Date = Date()
    ) {
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { return }
        records[index].status = .failed
        records[index].sessionID = sessionID
        records[index].finishedAt = date
        records[index].errorMessage = message
        persist()
    }

    func hasRun(_ taskID: UUID, scheduledAt: Date) -> Bool {
        records.contains { record in
            record.taskID == taskID && record.scheduledAt == scheduledAt
        }
    }

    @discardableResult
    func delete(_ taskID: UUID) -> ScheduledTask? {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return nil }
        let deleted = tasks.remove(at: index)
        persist()
        return deleted
    }

    func restore(_ task: ScheduledTask) {
        guard !tasks.contains(where: { $0.id == task.id }) else { return }
        tasks.append(task)
        tasks.sort { $0.createdAt < $1.createdAt }
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let snapshot = try? JSONDecoder().decode(ScheduleSnapshot.self, from: data) else {
            return
        }
        tasks = snapshot.tasks
        records = snapshot.records
    }

    private func persist() {
        let snapshot = ScheduleSnapshot(tasks: tasks, records: records)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    private func normalizedWeekday(for draft: ScheduleDraft) -> Int? {
        guard draft.recurrence == .weekly else { return nil }
        if let weekday = draft.weekday, (1...7).contains(weekday) {
            return weekday
        }
        return Calendar.current.component(.weekday, from: draft.time)
    }

    private func normalizedAccessMode(_ accessMode: AgentHostAccessMode) -> AgentHostAccessMode {
        accessMode == .full ? .full : .readOnly
    }
}
