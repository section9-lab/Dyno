import XCTest
@testable import PiWork

final class AgentHostLineFramerTests: XCTestCase {
    func testFramesSplitAndCoalescedLFRecords() {
        var framer = AgentHostLineFramer()

        XCTAssertEqual(framer.append(Data(#"{"id":"one""#.utf8)), [])
        XCTAssertEqual(
            framer.append(Data("}\n{\"id\":\"two\"}\r\npartial".utf8)),
            [Data(#"{"id":"one"}"#.utf8), Data(#"{"id":"two"}"#.utf8)]
        )
        XCTAssertEqual(framer.append(Data("-record\n".utf8)), [Data("partial-record".utf8)])
    }

    func testFramesLargeFragmentedRecordWithinOneSecond() {
        var framer = AgentHostLineFramer()
        let record = Data(repeating: 0x61, count: 4 * 1_024 * 1_024)
        var payload = record
        payload.append(0x0A)
        var records: [Data] = []

        let start = CFAbsoluteTimeGetCurrent()
        for offset in stride(from: 0, to: payload.count, by: 4_096) {
            let end = min(offset + 4_096, payload.count)
            records.append(contentsOf: framer.append(Data(payload[offset..<end])))
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        XCTAssertEqual(records, [record])
        XCTAssertLessThan(elapsed, 1, "Framing should scan each byte at most once")
    }
}
