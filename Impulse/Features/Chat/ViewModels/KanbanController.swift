import Foundation
import SwiftData

/// Stateless Kanban CRUD on `StoredKanbanTask` entities. Takes a
/// `ModelContext` per call; reads via `@Query` happen directly in the views.
@MainActor
struct KanbanController {

    func createTask(
        title rawTitle: String,
        priority: KanbanTaskPriority,
        status: KanbanTaskStatus,
        labels: [String] = [],
        projectPath: String?,
        selectedSessionID: String?,
        modelContext: ModelContext
    ) {
        guard let projectPath else { return }
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        let linked = selectedSessionID.map { [$0] } ?? []
        let task = StoredKanbanTask(
            projectPath: projectPath,
            title: title,
            status: status,
            priority: priority,
            primarySessionID: selectedSessionID,
            linkedSessionIDs: linked,
            labels: labels
        )
        modelContext.insert(task)
    }

    func setLabels(_ task: StoredKanbanTask, labels: [String]) {
        task.labels = labels
        task.updatedAt = Date()
    }

    func moveTask(_ task: StoredKanbanTask, to status: KanbanTaskStatus) {
        task.status = status
        task.updatedAt = Date()
    }

    func linkSession(_ task: StoredKanbanTask, sessionID: String?) {
        guard let sessionID else { return }
        var linked = task.linkedSessionIDs
        if !linked.contains(sessionID) {
            linked.append(sessionID)
        }
        task.linkedSessionIDs = linked
        if task.primarySessionID == nil {
            task.primarySessionID = sessionID
        }
        task.updatedAt = Date()
    }

    func deleteTask(_ task: StoredKanbanTask, modelContext: ModelContext) {
        modelContext.delete(task)
    }
}
