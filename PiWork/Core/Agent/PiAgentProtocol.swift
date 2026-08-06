import Foundation

/// Codable models for the `pi` coding-agent RPC-mode protocol
/// (https://github.com/earendil-works/pi, `pi --mode rpc`): line-delimited
/// JSON commands sent to stdin, and line-delimited JSON responses/events
/// read from stdout. See `docs/rpc.md` in the pi repo for the full spec;
/// this file covers the subset pi-work currently drives.

// MARK: - Client -> Agent commands

/// A command written to the agent process's stdin, one JSON object per line.
enum PiAgentCommand {
    case prompt(id: String, message: String)
    case steer(message: String)
    case followUp(message: String)
    case abort
    case newSession
    case getState(id: String)

    var id: String? {
        switch self {
        case .prompt(let id, _): return id
        case .getState(let id): return id
        default: return nil
        }
    }

    /// Encodes this command as a single line-delimited JSON object (including
    /// the trailing `\n` the protocol requires as the record delimiter).
    func encodedLine() throws -> Data {
        var payload: [String: Any] = [:]
        switch self {
        case .prompt(let id, let message):
            payload = ["id": id, "type": "prompt", "message": message]
        case .steer(let message):
            payload = ["type": "steer", "message": message]
        case .followUp(let message):
            payload = ["type": "follow_up", "message": message]
        case .abort:
            payload = ["type": "abort"]
        case .newSession:
            payload = ["type": "new_session"]
        case .getState(let id):
            payload = ["id": id, "type": "get_state"]
        }
        var data = try JSONSerialization.data(withJSONObject: payload, options: [])
        data.append(0x0A) // "\n"
        return data
    }
}

// MARK: - Agent -> Client responses & events

/// A single decoded line from the agent process's stdout: either a `response`
/// to a command (correlated by `id`), or an unsolicited streaming `event`.
enum PiAgentServerMessage {
    case response(PiAgentResponse)
    case event(PiAgentEvent)
    /// Anything we don't yet model explicitly. Keeps the app forward
    /// compatible with new event/response types instead of crashing.
    case unknown(type: String, raw: [String: Any])
}

struct PiAgentResponse {
    let id: String?
    let command: String
    let success: Bool
    /// Raw `data` payload (shape depends on `command`); callers decode the
    /// specific fields they need (e.g. `sessionId`, `messages`).
    let data: [String: Any]?
    let error: String?
}

enum PiAgentEvent {
    case agentStart
    case agentEnd(willRetry: Bool)
    case agentSettled
    case turnStart
    case turnEnd
    case messageStart
    case messageEnd
    /// Streaming delta while the assistant message is being generated.
    case textDelta(contentIndex: Int, delta: String)
    case thinkingDelta(contentIndex: Int, delta: String)
    case toolExecutionStart(toolCallId: String, toolName: String, argsSummary: String?)
    case toolExecutionUpdate(toolCallId: String, toolName: String)
    case toolExecutionEnd(toolCallId: String, toolName: String, isError: Bool)
    case extensionError(message: String)
    case other(type: String)
}

enum PiAgentDecodingError: Error {
    case notAJSONObject
    case missingType
}

/// Parses one JSONL line (without the trailing newline) into a server message.
/// Uses `JSONSerialization` (rather than `Decodable`) because the protocol's
/// per-`type` payload shapes vary enough that a single `Decodable` struct
/// hierarchy would need nearly the same manual dispatch anyway, and this way
/// unrecognized fields never fail decoding.
enum PiAgentMessageParser {
    static func parse(line: Data) throws -> PiAgentServerMessage {
        guard
            let obj = try JSONSerialization.jsonObject(with: line, options: []) as? [String: Any]
        else {
            throw PiAgentDecodingError.notAJSONObject
        }
        guard let type = obj["type"] as? String else {
            throw PiAgentDecodingError.missingType
        }

        if type == "response" {
            return .response(
                PiAgentResponse(
                    id: obj["id"] as? String,
                    command: obj["command"] as? String ?? "unknown",
                    success: obj["success"] as? Bool ?? false,
                    data: obj["data"] as? [String: Any],
                    error: obj["error"] as? String
                )
            )
        }

        if let event = parseEvent(type: type, obj: obj) {
            return .event(event)
        }
        return .unknown(type: type, raw: obj)
    }

    private static func parseEvent(type: String, obj: [String: Any]) -> PiAgentEvent? {
        switch type {
        case "agent_start":
            return .agentStart
        case "agent_end":
            return .agentEnd(willRetry: obj["willRetry"] as? Bool ?? false)
        case "agent_settled":
            return .agentSettled
        case "turn_start":
            return .turnStart
        case "turn_end":
            return .turnEnd
        case "message_start":
            return .messageStart
        case "message_end":
            return .messageEnd
        case "message_update":
            guard let ev = obj["assistantMessageEvent"] as? [String: Any],
                  let evType = ev["type"] as? String else { return .other(type: type) }
            let contentIndex = ev["contentIndex"] as? Int ?? 0
            switch evType {
            case "text_delta":
                return .textDelta(contentIndex: contentIndex, delta: ev["delta"] as? String ?? "")
            case "thinking_delta":
                return .thinkingDelta(contentIndex: contentIndex, delta: ev["delta"] as? String ?? "")
            default:
                return .other(type: "message_update.\(evType)")
            }
        case "tool_execution_start":
            let args = obj["args"] as? [String: Any]
            let argsSummary = args.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
                .flatMap { String(data: $0, encoding: .utf8) }
            return .toolExecutionStart(
                toolCallId: obj["toolCallId"] as? String ?? "",
                toolName: obj["toolName"] as? String ?? "",
                argsSummary: argsSummary
            )
        case "tool_execution_update":
            return .toolExecutionUpdate(
                toolCallId: obj["toolCallId"] as? String ?? "",
                toolName: obj["toolName"] as? String ?? ""
            )
        case "tool_execution_end":
            return .toolExecutionEnd(
                toolCallId: obj["toolCallId"] as? String ?? "",
                toolName: obj["toolName"] as? String ?? "",
                isError: obj["isError"] as? Bool ?? false
            )
        case "extension_error":
            return .extensionError(message: obj["message"] as? String ?? "unknown extension error")
        default:
            return .other(type: type)
        }
    }
}
