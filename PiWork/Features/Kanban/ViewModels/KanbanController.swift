import Foundation
import CoreData

/// Stateless Kanban CRUD on `StoredKanbanTask` entities. Takes an
/// `NSManagedObjectContext` per call; reads via `@FetchRequest` happen
/// directly in the views.
@MainActor
struct KanbanController {

    func createTask(
        title rawTitle: String,
        priority: KanbanTaskPriority,
        status: KanbanTaskStatus,
        labels: [String] = [],
        projectPath: String?,
        modelContext: NSManagedObjectContext
    ) {
        guard let projectPath else { return }
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        _ = StoredKanbanTask(
            context: modelContext,
            projectPath: projectPath,
            title: title,
            status: status,
            priority: priority,
            labels: labels
        )
        try? modelContext.save()
    }

    func setLabels(_ task: StoredKanbanTask, labels: [String]) {
        task.labels = labels
        task.updatedAt = Date()
        try? task.managedObjectContext?.save()
    }

    func moveTask(_ task: StoredKanbanTask, to status: KanbanTaskStatus) {
        task.status = status
        task.updatedAt = Date()
        try? task.managedObjectContext?.save()
    }

    func deleteTask(_ task: StoredKanbanTask, modelContext: NSManagedObjectContext) {
        modelContext.delete(task)
        try? modelContext.save()
    }
}
