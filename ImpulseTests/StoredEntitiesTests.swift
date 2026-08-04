import XCTest
import SwiftData
@testable import Impulse

final class StoredEntitiesTests: XCTestCase {
    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let container = try ModelContainer(
            for: StoredProject.self,
                StoredKanbanTask.self,
            configurations: .init(isStoredInMemoryOnly: true)
        )
        return (container, ModelContext(container))
    }

    func test_kanbanTask_statusEnumWrappersRoundTrip() {
        let task = StoredKanbanTask(
            projectPath: "/p",
            title: "t",
            status: .plan,
            priority: .high
        )
        XCTAssertEqual(task.status, .plan)
        XCTAssertEqual(task.priority, .high)

        task.status = .inProgress
        task.priority = .low
        XCTAssertEqual(task.statusRaw, KanbanTaskStatus.inProgress.rawValue)
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

    func test_kanbanTask_labelsTrimAndFilterEmptyValues() {
        let task = StoredKanbanTask(
            projectPath: "/p",
            title: "t",
            status: .plan,
            priority: .medium,
            labels: [" alpha ", "", "beta"]
        )
        XCTAssertEqual(task.labels, ["alpha", "beta"])
        XCTAssertEqual(task.labelsRaw, "alpha,beta")
    }

    func test_storedProject_displayNameUsesLastPathComponent() {
        XCTAssertEqual(StoredProject(path: "/Users/me/work/app").displayName, "app")
        XCTAssertEqual(StoredProject(path: "").displayName, "/")
    }

    func test_storedProject_roundTripsInModelContext() throws {
        let (_, context) = try makeContext()
        let project = StoredProject(path: "/Users/me/work/app")
        context.insert(project)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<StoredProject>())
        XCTAssertEqual(fetched.map(\.path), ["/Users/me/work/app"])
    }
}
