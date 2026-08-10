import XCTest
@testable import PiWork

@MainActor
final class ScheduleStoreTests: XCTestCase {
    private var storeURL: URL!

    override func setUp() {
        super.setUp()
        storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pi-work-schedule-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storeURL)
        storeURL = nil
        super.tearDown()
    }

    func testSavingNewDraftPersistsScheduleFields() throws {
        let store = ScheduleStore(storeURL: storeURL)
        let time = Date(timeIntervalSince1970: 1_800_000_000)

        let task = try store.save(
            ScheduleDraft(
                name: "Daily status",
                instruction: "Summarize open work.",
                recurrence: .weekdays,
                time: time,
                projectPath: "/tmp/pi-work"
            )
        )

        XCTAssertEqual(store.tasks, [task])
        XCTAssertEqual(task.name, "Daily status")
        XCTAssertEqual(task.instruction, "Summarize open work.")
        XCTAssertEqual(task.recurrence, .weekdays)
        XCTAssertEqual(task.time, time)
        XCTAssertEqual(task.projectPath, "/tmp/pi-work")
        XCTAssertTrue(task.isEnabled)
    }

    func testSavingExistingDraftUpdatesWithoutDuplicating() throws {
        let store = ScheduleStore(storeURL: storeURL)
        let original = try store.save(
            ScheduleDraft(
                name: "Original",
                instruction: "First instruction",
                recurrence: .daily,
                time: Date(timeIntervalSince1970: 1_800_000_000)
            )
        )
        var draft = ScheduleDraft(task: original)
        draft.name = "Updated"
        draft.instruction = "Updated instruction"

        let updated = try store.save(draft)

        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.name, "Updated")
        XCTAssertEqual(updated.instruction, "Updated instruction")
    }

    func testBlankNameIsRejected() {
        let store = ScheduleStore(storeURL: storeURL)
        let draft = ScheduleDraft(
            name: "   ",
            instruction: "Do the work",
            recurrence: .daily,
            time: Date()
        )

        XCTAssertThrowsError(try store.save(draft)) { error in
            XCTAssertEqual(error as? ScheduleValidationError, .nameRequired)
        }
        XCTAssertTrue(store.tasks.isEmpty)
    }

    func testBlankInstructionIsRejected() {
        let store = ScheduleStore(storeURL: storeURL)
        let draft = ScheduleDraft(
            name: "Daily status",
            instruction: "\n\t",
            recurrence: .daily,
            time: Date()
        )

        XCTAssertThrowsError(try store.save(draft)) { error in
            XCTAssertEqual(error as? ScheduleValidationError, .instructionRequired)
        }
        XCTAssertTrue(store.tasks.isEmpty)
    }

    func testEnabledStateCanBeChanged() throws {
        let store = ScheduleStore(storeURL: storeURL)
        let task = try store.save(validDraft())

        store.setEnabled(false, for: task.id)

        XCTAssertEqual(store.tasks.first?.isEnabled, false)
    }

    func testRunLifecyclePersistsCompletionDetails() throws {
        let store = ScheduleStore(storeURL: storeURL)
        let task = try store.save(validDraft())
        let runDate = Date(timeIntervalSince1970: 1_800_100_000)
        let finishDate = runDate.addingTimeInterval(12)

        let record = try XCTUnwrap(
            store.beginRun(for: task.id, scheduledAt: nil, at: runDate)
        )

        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.records.first?.taskID, task.id)
        XCTAssertEqual(store.records.first?.taskName, task.name)
        XCTAssertEqual(store.records.first?.startedAt, runDate)
        XCTAssertEqual(store.records.first?.status, .running)

        store.completeRun(
            record.id,
            sessionID: "scheduled-session",
            resultText: "Project analysis completed.",
            at: finishDate
        )

        XCTAssertEqual(store.records.first?.status, .completed)
        XCTAssertEqual(store.records.first?.sessionID, "scheduled-session")
        XCTAssertEqual(store.records.first?.resultText, "Project analysis completed.")
        XCTAssertEqual(store.records.first?.finishedAt, finishDate)
    }

    func testRunFailurePersistsItsMessage() throws {
        let store = ScheduleStore(storeURL: storeURL)
        let task = try store.save(validDraft())
        let record = try XCTUnwrap(store.beginRun(for: task.id))

        store.failRun(record.id, sessionID: "failed-session", message: "Model unavailable")

        XCTAssertEqual(store.records.first?.status, .failed)
        XCTAssertEqual(store.records.first?.sessionID, "failed-session")
        XCTAssertEqual(store.records.first?.errorMessage, "Model unavailable")
        XCTAssertNotNil(store.records.first?.finishedAt)
    }

    func testScheduledOccurrenceIsRecognizedAsAlreadyRun() throws {
        let store = ScheduleStore(storeURL: storeURL)
        let task = try store.save(validDraft())
        let occurrence = Date(timeIntervalSince1970: 1_800_100_000)

        _ = store.beginRun(for: task.id, scheduledAt: occurrence)

        XCTAssertTrue(store.hasRun(task.id, scheduledAt: occurrence))
        XCTAssertFalse(store.hasRun(task.id, scheduledAt: occurrence.addingTimeInterval(60)))
    }

    func testDeletedTaskCanBeRestored() throws {
        let store = ScheduleStore(storeURL: storeURL)
        let task = try store.save(validDraft())

        let deleted = store.delete(task.id)
        XCTAssertTrue(store.tasks.isEmpty)

        store.restore(try XCTUnwrap(deleted))

        XCTAssertEqual(store.tasks, [task])
    }

    func testSavedTasksReloadFromDisk() throws {
        let originalStore = ScheduleStore(storeURL: storeURL)
        let task = try originalStore.save(validDraft())

        let reloadedStore = ScheduleStore(storeURL: storeURL)

        XCTAssertEqual(reloadedStore.tasks, [task])
    }

    func testExistingScheduleFileLoadsWithSafeExecutionDefaults() throws {
        let taskID = UUID()
        let recordID = UUID()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = LegacyScheduleSnapshot(
            tasks: [
                LegacyScheduledTask(
                    id: taskID,
                    name: "Existing task",
                    instruction: "Analyze the project",
                    recurrence: .daily,
                    time: date,
                    projectPath: "/tmp/project",
                    isEnabled: true,
                    createdAt: date,
                    updatedAt: date
                )
            ],
            records: [
                LegacyScheduleRunRecord(
                    id: recordID,
                    taskID: taskID,
                    taskName: "Existing task",
                    startedAt: date,
                    status: .completed
                )
            ]
        )
        try JSONEncoder().encode(snapshot).write(to: storeURL)

        let store = ScheduleStore(storeURL: storeURL)

        XCTAssertEqual(store.tasks.first?.id, taskID)
        XCTAssertEqual(store.tasks.first?.unattendedAccessMode, .readOnly)
        XCTAssertNil(store.tasks.first?.weekday)
        XCTAssertEqual(store.records.first?.id, recordID)
        XCTAssertNil(store.records.first?.sessionID)
    }

    private func validDraft() -> ScheduleDraft {
        ScheduleDraft(
            name: "Daily status",
            instruction: "Summarize open work.",
            recurrence: .daily,
            time: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }
}

private struct LegacyScheduleSnapshot: Codable {
    let tasks: [LegacyScheduledTask]
    let records: [LegacyScheduleRunRecord]
}

private struct LegacyScheduledTask: Codable {
    let id: UUID
    let name: String
    let instruction: String
    let recurrence: ScheduleRecurrence
    let time: Date
    let projectPath: String?
    let isEnabled: Bool
    let createdAt: Date
    let updatedAt: Date
}

private struct LegacyScheduleRunRecord: Codable {
    let id: UUID
    let taskID: UUID
    let taskName: String
    let startedAt: Date
    let status: ScheduleRunStatus
}
