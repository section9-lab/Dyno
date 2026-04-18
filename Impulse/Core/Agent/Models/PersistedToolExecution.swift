import Foundation

struct PersistedToolExecution: Codable, Identifiable {
    let id: String
    let toolName: String
    let status: String
    let summary: String
    let output: String
}
