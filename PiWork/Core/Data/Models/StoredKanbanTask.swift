import Foundation
import CoreTransferable
import CoreData

enum KanbanTaskStatus: String, Codable, CaseIterable, Identifiable {
    /// Raw value stays "todo" to keep existing stored tasks loadable after
    /// the user-facing rename from "Todo" to "Plan".
    case plan = "todo"
    case inProgress
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plan:       return "Plan"
        case .inProgress: return "In Progress"
        case .done:       return "Done"
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

/// A Kanban card. Path-keyed against a `StoredProject` with legacy string link fields preserved for compatibility.
///
/// `linkedSessionIDs` and `labels` are comma-joined strings because the
/// original SwiftData layout had spotty support for `[String]` value-type
/// collections; the wrapper accessors keep callers strongly typed and the
/// on-disk representation unchanged after the move to Core Data.
@objc(StoredKanbanTask)
final class StoredKanbanTask: NSManagedObject, Identifiable {
    @NSManaged var id: String
    @NSManaged var projectPath: String
    @NSManaged var title: String
    /// Stored as the raw value of `KanbanTaskStatus`; access via `status`.
    @NSManaged var statusRaw: String
    /// Stored as the raw value of `KanbanTaskPriority`; access via `priority`.
    @NSManaged var priorityRaw: String
    @NSManaged var primarySessionID: String?
    /// Comma-joined session ids. Empty string == no links. Use
    /// `linkedSessionIDs` for typed access.
    @NSManaged var linkedSessionIDsRaw: String
    /// Comma-joined free-form label strings. Empty string == no labels. Use
    /// `labels` for typed access.
    @NSManaged var labelsRaw: String
    @NSManaged var assigneeName: String
    @NSManaged var notes: String
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date

    convenience init(
        context: NSManagedObjectContext,
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
        self.init(context: context)
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
        get { KanbanTaskStatus(rawValue: statusRaw) ?? .plan }
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

/// Transferable wrapper used for Kanban drag & drop. Core Data entities
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
