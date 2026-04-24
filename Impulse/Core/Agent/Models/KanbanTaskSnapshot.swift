import Foundation
import CoreTransferable

enum KanbanTaskStatus: String, Codable, CaseIterable, Identifiable {
    case plan
    case progress
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plan:
            return "Plan"
        case .progress:
            return "Progress"
        case .done:
            return "Done"
        }
    }
}

enum KanbanTaskPriority: String, Codable, CaseIterable, Identifiable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        }
    }
}

struct KanbanTaskSnapshot: Identifiable, Codable, Hashable, Transferable {
    let id: String
    let projectPath: String
    let title: String
    let status: KanbanTaskStatus
    let priority: KanbanTaskPriority
    let primarySessionID: String?
    let linkedSessionIDs: [String]
    let assigneeName: String
    let notes: String
    let createdAt: Date
    let updatedAt: Date

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}
