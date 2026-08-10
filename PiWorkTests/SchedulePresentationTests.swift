import XCTest
@testable import PiWork

final class SchedulePresentationTests: XCTestCase {
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

    func testScheduleToolbarOmitsTaskSortingControl() throws {
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

        XCTAssertFalse(toolbar.contains("ScheduleSortMenuLabel("))
        XCTAssertFalse(toolbar.contains("ScheduleSortOrder"))
        XCTAssertFalse(toolbar.contains("Menu {"))
    }

    func testRunHistoryExpandsPersistedResultsInPlace() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "PiWork/Features/Schedule/Views/ScheduleView.swift"
            ),
            encoding: .utf8
        )
        let rowStart = try XCTUnwrap(source.range(of: "private struct ScheduleHistoryRow"))
        let rowEnd = try XCTUnwrap(
            source.range(of: "private enum ScheduleWeekday", range: rowStart.upperBound..<source.endIndex)
        )
        let row = source[rowStart.lowerBound..<rowEnd.lowerBound]

        XCTAssertTrue(row.contains("@State private var isExpanded = false"))
        XCTAssertTrue(row.contains("record.resultText"))
        XCTAssertTrue(row.contains("Text(verbatim: detailText)"))
        XCTAssertTrue(row.contains(".textSelection(.enabled)"))
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

}
