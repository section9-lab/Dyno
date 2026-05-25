import Foundation

enum AgentToolExecutionStatus: String {
    case running
    case success
    case failed
}

/// Live state of one inner tool call inside a subagent. Mirrors a row's
/// shape but lives in-memory only — persisted at end of turn as a
/// `StoredSubagentToolRun`.
struct SubagentInnerToolState: Identifiable, Equatable {
    let id: String          // SDK toolUseID
    let toolName: String
    var status: AgentToolExecutionStatus
    var summary: String
    var output: String
}

/// Live state of one parallel subagent task within a `task` tool call.
/// `id` matches `SubagentTaskRequest.id`.
struct SubagentTaskLiveState: Identifiable, Equatable {
    let id: String
    let agentID: String
    var description: String          // from arguments JSON
    var status: AgentToolExecutionStatus
    var steps: Int
    var output: String
    var error: String?
    var innerTools: [SubagentInnerToolState]
}

struct AgentToolExecution: Identifiable, Equatable {
    let id: String
    let toolName: String
    let status: AgentToolExecutionStatus
    let summary: String
    let output: String
    /// JSON arguments captured at `toolStarted` time. `nil` only for the
    /// defensive fallback path when `finished` arrives without `started`.
    let argumentsJSON: String?
    /// Per-subagent live state — only populated when `toolName == "task"`
    /// and a `SubagentEventObserver` is installed.
    var subagentLive: [SubagentTaskLiveState]

    init(
        id: String,
        toolName: String,
        status: AgentToolExecutionStatus,
        summary: String,
        output: String,
        argumentsJSON: String? = nil,
        subagentLive: [SubagentTaskLiveState] = []
    ) {
        self.id = id
        self.toolName = toolName
        self.status = status
        self.summary = summary
        self.output = output
        self.argumentsJSON = argumentsJSON
        self.subagentLive = subagentLive
    }
}

/// One item in the in-flight assistant turn timeline. Text and tool calls
/// arrive interleaved from the model — preserving emission order is what
/// lets the UI render `text → tool → text → tool` instead of forcing a
/// fixed `tools-then-text` layout.
enum LiveTurnItem: Identifiable, Equatable {
    case text(id: UUID, content: String)
    case tool(AgentToolExecution)

    var id: String {
        switch self {
        case .text(let id, _): return "text-\(id.uuidString)"
        case .tool(let exec): return "tool-\(exec.id)"
        }
    }
}
