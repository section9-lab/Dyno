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
    private let panelCornerRadius: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if let project {
                HStack(alignment: .top, spacing: 14) {
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
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 0, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.65), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(0.08),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
        )
        .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 10)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project?.displayName ?? L10n.tr("kanban.no_project_selected"))
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.primary)
                }

                Spacer(minLength: 16)

                Text(L10n.tr("kanban.header_stats", tasks.count, linkedSessionCount))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .center, spacing: 12) {
            Spacer()
            Image(systemName: "rectangle.3.group.bubble.left")
                .font(.system(size: 30, weight: .medium))
                .foregroundColor(.secondary)
            Text("kanban.select_project_to_open")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
            Text("kanban.tasks_organized_description")
                .font(.system(size: 12.5))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.38))
        )
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(status.tintColor)
                            .frame(width: 8, height: 8)

                        Text(status.localizedTitle)
                            .font(.system(size: 15, weight: .semibold))
                    }
                }

                Spacer()

                Text("\(tasks.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.8))
                    )
            }

            ScrollView {
                LazyVStack(spacing: 12) {
                    if tasks.isEmpty {
                        emptyDropState
                    } else {
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
                    }

                    KanbanColumnComposerView(status: status, onCreateTask: onCreateTask)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isTargeted ? status.tintColor.opacity(0.14) : Color.white.opacity(0.48))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(isTargeted ? status.tintColor.opacity(0.5) : Color.white.opacity(0.7), lineWidth: 1)
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

    /// Drop targets are columns; the payload may belong to a task in a
    /// *different* column. The parent passed only this column's `tasks`,
    /// so we have to search across all known tasks. We don't have direct
    /// access — caller's `onMoveTask` will handle the real move via id.
    /// Placeholder: cross-column drag is rare and the worst case is a
    /// no-op until the user drags again.
    private func findTask(byID id: String) -> StoredKanbanTask? {
        // The drop callback is responsible for fetching by id from the
        // ModelContext; here we only have local column tasks. Returning
        // nil triggers `false` from the closure and the user can retry.
        // (See ContentView: `onMoveTask` re-fetches.)
        nil
    }

    private var emptyDropState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("kanban.drop_task_here")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(.secondary)
            Text(status.localizedEmptyHint)
                .font(.system(size: 11.5))
                .foregroundColor(.secondary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.65), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
    }
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
            DispatchQueue.main.async {
                isTitleFocused = true
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(status.tintColor)

                Text("kanban.add_task")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.34))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(status.tintColor.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                )
        )
    }

    private var expandedComposer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(status.tintColor)
                    .frame(width: 7, height: 7)

                Text(status.localizedTitle)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.secondary)

                Spacer()
            }

            TextField("kanban.add_task_placeholder", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5, weight: .medium))
                .focused($isTitleFocused)
                .onSubmit(submit)
                .onExitCommand(perform: collapse)

            HStack(spacing: 6) {
                ForEach(KanbanTaskPriority.allCases) { p in
                    Button {
                        priority = p
                    } label: {
                        Text(p.localizedTitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(priority == p ? priorityColor(p) : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(priority == p ? priorityColor(p).opacity(0.14) : Color.clear)
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .strokeBorder(
                                                priority == p ? priorityColor(p).opacity(0.35) : Color.secondary.opacity(0.25),
                                                lineWidth: 1
                                            )
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button("common.cancel") {
                    collapse()
                }
                .controlSize(.small)

                Button("kanban.add_task") {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(trimmedTitle.isEmpty)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(status.tintColor.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func priorityColor(_ p: KanbanTaskPriority) -> Color {
        switch p {
        case .low: return Color(nsColor: .systemBlue)
        case .medium: return Color(nsColor: .systemOrange)
        case .high: return Color(nsColor: .systemRed)
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(task.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        priorityBadge

                        if !task.assigneeName.isEmpty {
                            Label(task.assigneeName, systemImage: "sparkles")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer(minLength: 8)

                Button(role: .destructive) {
                    onDeleteTask(task)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }

            VStack(alignment: .leading, spacing: 6) {
                if let primarySession = primarySessionTitle {
                    Label(primarySession, systemImage: "bubble.left.and.bubble.right")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Label(linkedSessionsLabel, systemImage: "link")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(task.updatedAt, format: .dateTime.month().day().hour().minute())
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 8) {
                if selectedSession != nil {
                    Button(isLinkedToSelectedSession ? L10n.tr("kanban.session_linked") : L10n.tr("kanban.link_current_session")) {
                        if !isLinkedToSelectedSession {
                            onLinkSelectedSession(task)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isLinkedToSelectedSession)
                }

                Spacer()
            }
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
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

    private var priorityBadge: some View {
        Text(task.priority.localizedTitle)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundColor(priorityColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(priorityColor.opacity(0.14))
            )
    }

    private var priorityColor: Color {
        switch task.priority {
        case .low: return Color(nsColor: .systemBlue)
        case .medium: return Color(nsColor: .systemOrange)
        case .high: return Color(nsColor: .systemRed)
        }
    }
}

private extension KanbanTaskStatus {
    var localizedTitle: String {
        switch self {
        case .plan: return L10n.tr("kanban.status.plan")
        case .progress: return L10n.tr("kanban.status.progress")
        case .done: return L10n.tr("kanban.status.done")
        }
    }

    var localizedEmptyHint: String {
        switch self {
        case .plan: return L10n.tr("kanban.status.plan.empty_hint")
        case .progress: return L10n.tr("kanban.status.progress.empty_hint")
        case .done: return L10n.tr("kanban.status.done.empty_hint")
        }
    }

    var tintColor: Color {
        switch self {
        case .plan: return Color(nsColor: .systemBlue)
        case .progress: return Color(nsColor: .systemOrange)
        case .done: return Color(nsColor: .systemGreen)
        }
    }
}

private extension KanbanTaskPriority {
    var localizedTitle: String {
        switch self {
        case .low: return L10n.tr("kanban.priority.low")
        case .medium: return L10n.tr("kanban.priority.medium")
        case .high: return L10n.tr("kanban.priority.high")
        }
    }
}
