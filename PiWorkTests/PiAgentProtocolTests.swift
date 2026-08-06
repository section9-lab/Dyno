import XCTest
@testable import PiWork

final class PiAgentProtocolTests: XCTestCase {
    func testParsesGetStateResponse() throws {
        let line = """
        {"id":"1","type":"response","command":"get_state","success":true,"data":{"messageCount":0}}
        """
        let message = try PiAgentMessageParser.parse(line: Data(line.utf8))
        guard case .response(let response) = message else {
            return XCTFail("expected .response, got \(message)")
        }
        XCTAssertEqual(response.id, "1")
        XCTAssertEqual(response.command, "get_state")
        XCTAssertTrue(response.success)
    }

    func testParsesTextDeltaEvent() throws {
        let line = """
        {"type":"message_update","assistantMessageEvent":{"type":"text_delta","contentIndex":0,"delta":"Hello"}}
        """
        let message = try PiAgentMessageParser.parse(line: Data(line.utf8))
        guard case .event(.textDelta(let index, let delta)) = message else {
            return XCTFail("expected .event(.textDelta), got \(message)")
        }
        XCTAssertEqual(index, 0)
        XCTAssertEqual(delta, "Hello")
    }

    func testParsesToolExecutionStart() throws {
        let line = """
        {"type":"tool_execution_start","toolCallId":"call_1","toolName":"bash","args":{"command":"ls"}}
        """
        let message = try PiAgentMessageParser.parse(line: Data(line.utf8))
        guard case .event(.toolExecutionStart(let id, let name, _)) = message else {
            return XCTFail("expected .event(.toolExecutionStart), got \(message)")
        }
        XCTAssertEqual(id, "call_1")
        XCTAssertEqual(name, "bash")
    }

    func testEncodesPromptCommand() throws {
        let command = PiAgentCommand.prompt(id: "abc", message: "Hello, world!")
        let data = try command.encodedLine()
        let text = String(data: data, encoding: .utf8)!
        XCTAssertTrue(text.hasSuffix("\n"))
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["id"] as? String, "abc")
        XCTAssertEqual(obj["type"] as? String, "prompt")
        XCTAssertEqual(obj["message"] as? String, "Hello, world!")
    }
}
