import AppKit
import SwiftUI

struct KanbanPanelView: View {
    let project: StoredProject?
    let selectedSession: StoredSession?
    let tasks: [StoredKanbanTask]
    /// All sessions for the project — used to look up titles for primary
    /// session links inside cards. Filtered by the parent.
    let projectSessions: [StoredSession]
    var onCreateTask: (String, KanbanTaskPriority, KanbanTaskStatus) -> Void
    var onMoveTask: (StoredKanbanTask, KanbanTaskStatus) -> Void
    var onLinkSelectedSession: (StoredKanbanTask) -> Void
    var onDeleteTask: (StoredKanbanTask) -> Void

    private let columns = KanbanTaskStatus.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            Divider().opacity(0.5)

            if let project {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(columns) { status in
                        KanbanColumnView(
                            status: status,
                            tasks: tasks.filter { $0.status == status },
                            project: project,
                            selectedSession: selectedSession,
                            projectSessions: projectSessions,
                            onCreateTask: onCreateTask,
                            onMoveTask: onMoveTask,
                            onLinkSelectedSession: onLinkSelectedSession,
                            onDeleteTask: onDeleteTask
                        )
                    }
                }
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(project?.displayName ?? L10n.tr("kanban.no_project_selected"))
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.primary)

            Spacer(minLength: 12)

            HStack(spacing: 16) {
                metricLabel(value: tasks.count, label: "kanban.tasks")
                metricLabel(value: linkedSessionCount, label: "kanban.sessions")
            }
        }
    }

    private func metricLabel(value: Int, label: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text("\(value)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.primary.opacity(0.85))
        }
    }

    private var emptyState: some View {
        VStack(alignment: .center, spacing: 10) {
            Spacer()
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 26, weight: .light))
                .foregroundColor(.secondary.opacity(0.7))
            Text("kanban.select_project_to_open")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.primary.opacity(0.85))
            Text("kanban.tasks_organized_description")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var linkedSessionCount: Int {
        Set(tasks.flatMap(\.linkedSessionIDs)).count
    }
}

private struct KanbanColumnView: View {
    let status: KanbanTaskStatus
    let tasks: [StoredKanbanTask]
    let project: StoredProject
    let selectedSession: StoredSession?
    let projectSessions: [StoredSession]
    var onCreateTask: (String, KanbanTaskPriority, KanbanTaskStatus) -> Void
    var onMoveTask: (StoredKanbanTask, KanbanTaskStatus) -> Void
    var onLinkSelectedSession: (StoredKanbanTask) -> Void
    var onDeleteTask: (StoredKanbanTask) -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            columnHeader

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(tasks) { task in
                        KanbanTaskCardView(
                            task: task,
                            projectSessions: projectSessions,
                            selectedSession: selectedSession,
                            onLinkSelectedSession: onLinkSelectedSession,
                            onDeleteTask: onDeleteTask
                        )
                        .draggable(KanbanTaskDragPayload(id: task.id))
                    }

                    KanbanColumnComposerView(status: status, onCreateTask: onCreateTask)
                }
                .padding(.bottom, 4)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isTargeted ? status.tintColor.opacity(0.06) : Color.secondary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isTargeted ? status.tintColor.opacity(0.35) : Color.clear,
                    lineWidth: 1
                )
        )
        .dropDestination(for: KanbanTaskDragPayload.self) { dropped, _ in
            guard let payload = dropped.first,
                  let task = tasks.first(where: { $0.id == payload.id })
                      ?? findTask(byID: payload.id)
            else { return false }
            onMoveTask(task, status)
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(status.tintColor)
                .frame(width: 6, height: 6)

            Text(status.localizedTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary.opacity(0.85))

            Text("\(tasks.count)")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    /// See parent — cross-column drag would need a ModelContext lookup we
    /// don't have here. The parent's `onMoveTask` re-fetches by id.
    private func findTask(byID id: String) -> StoredKanbanTask? { nil }
}

private struct KanbanColumnComposerView: View {
    let status: KanbanTaskStatus
    var onCreateTask: (String, KanbanTaskPriority, KanbanTaskStatus) -> Void

    @State private var isExpanded = false
    @State private var title = ""
    @State private var priority: KanbanTaskPriority = .medium
    @FocusState private var isTitleFocused: Bool

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Group {
            if isExpanded {
                expandedComposer
            } else {
                collapsedButton
            }
        }
        .animation(.easeOut(duration: 0.16), value: isExpanded)
    }

    private var collapsedButton: some View {
        Button {
            isExpanded = true
            DispatchQueue.main.async { isTitleFocused = true }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("kanban.add_task")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var expandedComposer: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("kanban.add_task_placeholder", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .focused($isTitleFocused)
                .onSubmit(submit)
                .onExitCommand(perform: collapse)

            HStack(spacing: 6) {
                ForEach(KanbanTaskPriority.allCases) { p in
                    priorityChip(p)
                }
                Spacer()
                Button("common.cancel") { collapse() }
                    .controlSize(.small)
                Button("kanban.add_task") { submit() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(trimmedTitle.isEmpty)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
                )
        )
    }

    private func priorityChip(_ p: KanbanTaskPriority) -> some View {
        Button {
            priority = p
        } label: {
            Text(p.localizedTitle)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(priority == p ? .primary : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule(style: .continuous)
                        .fill(priority == p ? Color.secondary.opacity(0.12) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    private func submit() {
        guard !trimmedTitle.isEmpty else { return }
        onCreateTask(trimmedTitle, priority, status)
        title = ""
        priority = .medium
        isExpanded = false
        isTitleFocused = false
    }

    private func collapse() {
        title = ""
        priority = .medium
        isExpanded = false
        isTitleFocused = false
    }
}

private struct KanbanTaskCardView: View {
    let task: StoredKanbanTask
    let projectSessions: [StoredSession]
    let selectedSession: StoredSession?
    var onLinkSelectedSession: (StoredKanbanTask) -> Void
    var onDeleteTask: (StoredKanbanTask) -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                if task.priority == .high {
                    Circle()
                        .fill(Color(nsColor: .systemRed))
                        .frame(width: 6, height: 6)
                        .padding(.top, 5)
                }

                Text(task.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isHovered {
                    Button(role: .destructive) { onDeleteTask(task) } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }

            HStack(spacing: 10) {
                if task.priority != .medium {
                    Text(task.priority.localizedTitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(priorityForeground)
                }

                if !task.linkedSessionIDs.isEmpty {
                    Label(linkedSessionsLabel, systemImage: "link")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .labelStyle(.titleAndIcon)
                }

                Spacer(minLength: 0)

                Text(task.updatedAt, format: .dateTime.month().day())
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(isHovered ? 0.22 : 0.12), lineWidth: 1)
                )
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
        .contextMenu {
            if selectedSession != nil && !isLinkedToSelectedSession {
                Button("kanban.link_current_session", systemImage: "link.badge.plus") {
                    onLinkSelectedSession(task)
                }
            }
            Button("kanban.delete_task", systemImage: "trash", role: .destructive) {
                onDeleteTask(task)
            }
        }
    }

    private var primarySessionTitle: String? {
        guard let primarySessionID = task.primarySessionID else { return nil }
        return projectSessions.first(where: { $0.id == primarySessionID })?.title
    }

    private var isLinkedToSelectedSession: Bool {
        guard let selectedSession else { return false }
        return task.linkedSessionIDs.contains(selectedSession.id)
    }

    private var linkedSessionsLabel: String {
        task.linkedSessionIDs.count == 1
            ? L10n.tr("kanban.one_session")
            : L10n.tr("kanban.sessions_count", task.linkedSessionIDs.count)
    }

    private var priorityForeground: Color {
        switch task.priority {
        case .low:    return .secondary
        case .medium: return .secondary
        case .high:   return Color(nsColor: .systemRed)
        }
    }
}

private extension KanbanTaskStatus {
    var localizedTitle: String {
        switch self {
        case .plan:     return L10n.tr("kanban.status.plan")
        case .progress: return L10n.tr("kanban.status.progress")
        case .done:     return L10n.tr("kanban.status.done")
        }
    }

    var localizedEmptyHint: String {
        switch self {
        case .plan:     return L10n.tr("kanban.status.plan.empty_hint")
        case .progress: return L10n.tr("kanban.status.progress.empty_hint")
        case .done:     return L10n.tr("kanban.status.done.empty_hint")
        }
    }

    /// Muted status accents — Liner-style. Only used as a 6pt dot in the
    /// column header; the rest of the chrome stays monochrome.
    var tintColor: Color {
        switch self {
        case .plan:     return Color.secondary
        case .progress: return Color(nsColor: .systemBlue)
        case .done:     return Color(nsColor: .systemGreen)
        }
    }
}

private extension KanbanTaskPriority {
    var localizedTitle: String {
        switch self {
        case .low:    return L10n.tr("kanban.priority.low")
        case .medium: return L10n.tr("kanban.priority.medium")
        case .high:   return L10n.tr("kanban.priority.high")
        }
    }
}
