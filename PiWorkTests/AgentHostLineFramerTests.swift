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
}
