import Foundation
import SwiftData

@available(macOS 14.0, *)
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
        modelContext: ModelContext
    ) {
        guard let projectPath else { return }
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        let task = StoredKanbanTask(
            projectPath: projectPath,
            title: title,
            status: status,
            priority: priority,
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

    func deleteTask(_ task: StoredKanbanTask, modelContext: ModelContext) {
        modelContext.delete(task)
    }
}
