import Foundation

enum AgentToolExecutionStatus: String {
    case success
    case failed
}

struct AgentToolExecution: Identifiable, Equatable {
    let id: String
    let toolName: String
    let status: AgentToolExecutionStatus
    let summary: String
    let output: String
}
