import XCTest
@testable import PiWork

@MainActor
final class SessionOpenPerformanceTests: XCTestCase {
    func testTraceRecordsCumulativeAndStageDurationsUntilFirstFrame() {
        var now: UInt64 = 1_000_000_000
        var events: [SessionOpenPerformanceEvent] = []
        let tracer = SessionOpenPerformanceTracer(
            nowNanoseconds: { now },
            sink: { events.append($0) }
        )

        let traceID = tracer.begin(sessionID: "session-one", profile: .work)
        now += 25_000_000
        tracer.mark(
            traceID: traceID,
            stage: .snapshotCompleted,
            messageCount: 40,
            hasEarlierMessages: true
        )
        now += 40_000_000
        tracer.finishActive(sessionID: "session-one", transcriptCount: 21)
        tracer.markActive(sessionID: "session-one", stage: .presentationReady)

        XCTAssertEqual(events.map(\.stage), [
            .requested,
            .snapshotCompleted,
            .firstFrame
        ])
        XCTAssertEqual(events.map(\.traceID), [traceID, traceID, traceID])
        XCTAssertEqual(events.map(\.elapsedMilliseconds), [0, 25, 65])
        XCTAssertEqual(events.map(\.stageMilliseconds), [0, 25, 40])
        XCTAssertEqual(events[1].messageCount, 40)
        XCTAssertEqual(events[1].hasEarlierMessages, true)
        XCTAssertEqual(events[2].transcriptCount, 21)
    }
}
