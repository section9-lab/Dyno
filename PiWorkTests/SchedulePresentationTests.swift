import XCTest
@testable import PiWork

final class SchedulePresentationTests: XCTestCase {
    func testNameSortUsesLocalizedCaseInsensitiveOrder() {
        let tasks = [
            makeTask(name: "Zulu", createdAt: Date(timeIntervalSince1970: 1)),
            makeTask(name: "alpha", createdAt: Date(timeIntervalSince1970: 2))
        ]

        let sorted = ScheduleSortOrder.name.apply(to: tasks)

        XCTAssertEqual(sorted.map(\.name), ["alpha", "Zulu"])
    }

    func testNewestSortUsesCreationDateDescending() {
        let tasks = [
            makeTask(name: "Older", createdAt: Date(timeIntervalSince1970: 1)),
            makeTask(name: "Newer", createdAt: Date(timeIntervalSince1970: 2))
        ]

        let sorted = ScheduleSortOrder.newest.apply(to: tasks)

        XCTAssertEqual(sorted.map(\.name), ["Newer", "Older"])
    }

    func testTimeSortUsesHourAndMinute() {
        let calendar = Calendar(identifier: .gregorian)
        let later = calendar.date(from: DateComponents(hour: 18, minute: 30))!
        let earlier = calendar.date(from: DateComponents(hour: 9, minute: 30))!
        let tasks = [
            makeTask(name: "Later", time: later),
            makeTask(name: "Earlier", time: earlier)
        ]

        let sorted = ScheduleSortOrder.time.apply(to: tasks, calendar: calendar)

        XCTAssertEqual(sorted.map(\.name), ["Earlier", "Later"])
    }

    func testRecurrencesExposeStableLocalizationKeys() {
        XCTAssertEqual(ScheduleRecurrence.daily.localizationKey, "schedule.recurrence.daily")
        XCTAssertEqual(
            ScheduleRecurrence.weekdays.localizationKey,
            "schedule.recurrence.weekdays"
        )
        XCTAssertEqual(ScheduleRecurrence.weekly.localizationKey, "schedule.recurrence.weekly")
    }

    func testScheduleSidebarDestinationRoutesToScheduleView() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "PiWork/App/Root/ContentView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("selectedCustomDestination == .schedule"))
        XCTAssertTrue(source.contains("ScheduleView("))
    }

    func testSortMenuUsesCustomPlainRoundedControl() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "PiWork/Features/Schedule/Views/ScheduleView.swift"
            ),
            encoding: .utf8
        )
        let toolbarStart = try XCTUnwrap(source.range(of: "private var sectionToolbar"))
        let toolbarEnd = try XCTUnwrap(
            source.range(of: "private func sectionButton", range: toolbarStart.upperBound..<source.endIndex)
        )
        let toolbar = source[toolbarStart.lowerBound..<toolbarEnd.lowerBound]

        XCTAssertTrue(toolbar.contains("ScheduleSortMenuLabel("))
        XCTAssertTrue(toolbar.contains(".buttonStyle(.plain)"))
        XCTAssertTrue(toolbar.contains(".frame(width: 128, height: 36)"))
    }

    func testScheduleCardsUseAdaptiveColumnsFromTwoAtMinimumWindowWidth() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "PiWork/Features/Schedule/Views/ScheduleView.swift"
            ),
            encoding: .utf8
        )
        let gridStart = try XCTUnwrap(source.range(of: "private var taskGrid"))
        let gridEnd = try XCTUnwrap(
            source.range(of: "private var taskEmptyState", range: gridStart.upperBound..<source.endIndex)
        )
        let grid = source[gridStart.lowerBound..<gridEnd.lowerBound]

        XCTAssertTrue(
            grid.contains(
                "GridItem(.adaptive(minimum: 260), spacing: 16, alignment: .top)"
            )
        )
    }

    private func makeTask(
        name: String,
        time: Date = Date(timeIntervalSince1970: 0),
        createdAt: Date = Date(timeIntervalSince1970: 0)
    ) -> ScheduledTask {
        ScheduledTask(
            id: UUID(),
            name: name,
            instruction: "Instruction",
            recurrence: .daily,
            time: time,
            projectPath: nil,
            isEnabled: true,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }
}
