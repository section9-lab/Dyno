import Foundation
import CoreTransferable
import SwiftData

enum KanbanTaskStatus: String, Codable, CaseIterable, Identifiable {
    case todo
    case inProgress
    case pendingReview
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todo:          return "Todo"
        case .inProgress:    return "In Progress"
        case .pendingReview: return "Pending Review"
        case .done:          return "Done"
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
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}

/// A Kanban card. Path-keyed against a `StoredProject` (no SwiftData
/// relationship — explicit fetch by `projectPath`, same convention as
/// `StoredSession`).
///
/// `linkedSessionIDs` and `labels` are comma-joined strings because SwiftData
/// has spotty support for `[String]` value-type collections; the wrapper
/// accessors keep callers strongly typed.
@Model
final class StoredKanbanTask {
    @Attribute(.unique) var id: String
    var projectPath: String
    var title: String
    /// Stored as the raw value of `KanbanTaskStatus`; access via `status`.
    var statusRaw: String
    /// Stored as the raw value of `KanbanTaskPriority`; access via `priority`.
    var priorityRaw: String
    var primarySessionID: String?
    /// Comma-joined session ids. Empty string == no links. Use
    /// `linkedSessionIDs` for typed access.
    var linkedSessionIDsRaw: String
    /// Comma-joined free-form label strings. Empty string == no labels. Use
    /// `labels` for typed access.
    var labelsRaw: String = ""
    var assigneeName: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        projectPath: String,
        title: String,
        status: KanbanTaskStatus,
        priority: KanbanTaskPriority,
        primarySessionID: String? = nil,
        linkedSessionIDs: [String] = [],
        labels: [String] = [],
        assigneeName: String = "AI",
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectPath = projectPath
        self.title = title
        self.statusRaw = status.rawValue
        self.priorityRaw = priority.rawValue
        self.primarySessionID = primarySessionID
        self.linkedSessionIDsRaw = linkedSessionIDs.joined(separator: ",")
        self.labelsRaw = labels.joined(separator: ",")
        self.assigneeName = assigneeName
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var status: KanbanTaskStatus {
        get { KanbanTaskStatus(rawValue: statusRaw) ?? .todo }
        set { statusRaw = newValue.rawValue }
    }

    var priority: KanbanTaskPriority {
        get { KanbanTaskPriority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }

    var linkedSessionIDs: [String] {
        get {
            linkedSessionIDsRaw.isEmpty
                ? []
                : linkedSessionIDsRaw.split(separator: ",").map(String.init)
        }
        set { linkedSessionIDsRaw = newValue.joined(separator: ",") }
    }

    var labels: [String] {
        get {
            labelsRaw.isEmpty
                ? []
                : labelsRaw.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
        }
        set {
            labelsRaw = newValue
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: ",")
        }
    }
}

/// Transferable wrapper used for Kanban drag & drop. SwiftData entities
/// can't directly conform to `Transferable`, so we transfer just the id and
/// re-fetch on the drop side. Lives separately from `KanbanTaskSnapshot`'s
/// own `transferRepresentation`; old call sites keep using snapshot drag
/// until the legacy type is removed.
struct KanbanTaskDragPayload: Codable, Transferable {
    let id: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}
