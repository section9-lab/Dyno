import XCTest
import SwiftData
@testable import Impulse

/// Smoke tests for the SwiftData entities. Verifies basic construction +
/// relationship cascade. Schema-stable raw values (role / status strings)
/// are pinned here so a careless rename shows up in code review.
final class StoredEntitiesTests: XCTestCase {

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let container = try ModelContainer(
            for: StoredProject.self,
                StoredSession.self,
                StoredMessage.self,
                StoredToolRun.self,
                StoredCompactionSummary.self,
                StoredKanbanTask.self,
            configurations: .init(isStoredInMemoryOnly: true)
        )
        return (container, ModelContext(container))
    }

    // MARK: - Schema-stable string contracts

    /// `StoredMessage.role` raw values are written to disk. Renaming them
    /// silently changes the on-disk format.
    func test_messageRoleStringsArePinned() {
        let session = StoredSession(id: "s", projectPath: "/p", title: "t", startedAt: Date())
        let user = StoredMessage(timestamp: Date(), role: "user", content: "x", session: session)
        let assistant = StoredMessage(timestamp: Date(), role: "assistant", content: "y", session: session)
        XCTAssertTrue(user.isUser)
        XCTAssertFalse(assistant.isUser)
    }

    /// Tool run `status` raw values are surfaced to the UI's
    /// `AgentToolExecutionStatus` mapping. Pin the strings.
    func test_toolRunStatusStringsArePinned() {
        let run = StoredToolRun(
            id: "1", timestamp: Date(), toolName: "read",
            status: "success", summary: "", output: ""
        )
        XCTAssertEqual(run.status, "success")

        run.status = "running"
        XCTAssertEqual(run.status, "running")

        run.status = "failed"
        XCTAssertEqual(run.status, "failed")
    }

    // MARK: - Cascade delete

    /// Deleting a session cascades to its messages, tool runs, and
    /// compaction summaries via SwiftData inverse relationships.
    func test_deleteSession_cascadesToChildren() throws {
        let (_, context) = try makeContext()
        let session = StoredSession(id: "s1", projectPath: "/p", title: "t", startedAt: Date())
        context.insert(session)
        let m = StoredMessage(timestamp: Date(), role: "user", content: "hi", session: session)
        let t = StoredToolRun(id: "tr1", timestamp: Date(), toolName: "read", status: "success", summary: "", output: "", session: session)
        let s = StoredCompactionSummary(timestamp: Date(), content: "summary", session: session)
        context.insert(m)
        context.insert(t)
        context.insert(s)
        try context.save()

        XCTAssertEqual(session.messages.count, 1)
        XCTAssertEqual(session.toolRuns.count, 1)
        XCTAssertEqual(session.compactionSummaries.count, 1)

        context.delete(session)
        try context.save()

        let remainingMessages = try context.fetch(FetchDescriptor<StoredMessage>())
        let remainingToolRuns = try context.fetch(FetchDescriptor<StoredToolRun>())
        let remainingSummaries = try context.fetch(FetchDescriptor<StoredCompactionSummary>())
        XCTAssertEqual(remainingMessages.count, 0)
        XCTAssertEqual(remainingToolRuns.count, 0)
        XCTAssertEqual(remainingSummaries.count, 0)
    }

    // MARK: - StoredKanbanTask wrappers

    func test_kanbanTask_statusEnumWrappersRoundTrip() {
        let task = StoredKanbanTask(
            projectPath: "/p",
            title: "t",
            status: .plan,
            priority: .high
        )
        XCTAssertEqual(task.status, .plan)
        XCTAssertEqual(task.priority, .high)

        task.status = .progress
        task.priority = .low
        XCTAssertEqual(task.statusRaw, "progress")
        XCTAssertEqual(task.priorityRaw, "low")
    }

    func test_kanbanTask_linkedSessionIDsRoundTrip() {
        let task = StoredKanbanTask(
            projectPath: "/p",
            title: "t",
            status: .plan,
            priority: .medium,
            linkedSessionIDs: ["a", "b", "c"]
        )
        XCTAssertEqual(task.linkedSessionIDs, ["a", "b", "c"])
        XCTAssertEqual(task.linkedSessionIDsRaw, "a,b,c")
    }

    func test_kanbanTask_linkedSessionIDs_emptyHandled() {
        let task = StoredKanbanTask(
            projectPath: "/p",
            title: "t",
            status: .plan,
            priority: .medium
        )
        XCTAssertEqual(task.linkedSessionIDs, [])
        XCTAssertEqual(task.linkedSessionIDsRaw, "")

        task.linkedSessionIDs = ["only"]
        XCTAssertEqual(task.linkedSessionIDsRaw, "only")
    }

    // MARK: - StoredProject

    func test_storedProject_displayNameUsesLastPathComponent() {
        XCTAssertEqual(StoredProject(path: "/Users/me/work/app").displayName, "app")
        // Empty path: `URL(fileURLWithPath: "")` resolves to "/" via Foundation,
        // so `displayName` ends up as "/", not "". Pin that behavior so any
        // future change to the empty-path fallback is intentional.
        XCTAssertEqual(StoredProject(path: "").displayName, "/")
    }
}
