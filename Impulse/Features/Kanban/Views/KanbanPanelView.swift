import AppKit
import SwiftUI

struct KanbanPanelView: View {
    /// All projects available — used to populate the picker. The header
    /// picker drives `selectedProjectPath`; tasks/sessions are filtered by
    /// the parent based on that selection.
    let projects: [StoredProject]
    /// Which project the kanban currently scopes to. `nil` means "all
    /// projects" — the default aggregate view.
    @Binding var selectedProjectPath: String?
    let selectedSession: StoredSession?
    /// All tasks across the workspace. The view filters by
    /// `selectedProjectPath` itself so the parent doesn't have to recompute
    /// when the picker changes.
    let tasks: [StoredKanbanTask]
    /// Sessions for the currently-scoped project (or all sessions when in
    /// aggregate mode). Used to look up titles for primary-session links.
    let projectSessions: [StoredSession]
    var onCreateTask: (String, KanbanTaskPriority, KanbanTaskStatus) -> Void
    var onMoveTask: (StoredKanbanTask, KanbanTaskStatus) -> Void
    var onLinkSelectedSession: (StoredKanbanTask) -> Void
    var onDeleteTask: (StoredKanbanTask) -> Void

    private let columns = KanbanTaskStatus.allCases

    /// In aggregate mode, the composer needs to know which project a new
    /// task belongs to. Default to the first available project; user can
    /// switch via the composer's own picker (kept inline to avoid extra UI
    /// when only one project exists).
    @State private var composerProjectPath: String?

    private var scopedProject: StoredProject? {
        guard let path = selectedProjectPath else { return nil }
        return projects.first(where: { $0.path == path })
    }

    private var scopedTasks: [StoredKanbanTask] {
        guard let path = selectedProjectPath else { return tasks }
        return tasks.filter { $0.projectPath == path }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            Divider().opacity(0.5)

            HStack(alignment: .top, spacing: 16) {
                ForEach(columns) { status in
                    KanbanColumnView(
                        status: status,
                        tasks: scopedTasks.filter { $0.status == status },
                        showProjectName: selectedProjectPath == nil,
                        projectsByPath: projectsByPath,
                        composerProjectPath: effectiveComposerProjectPath,
                        canCompose: effectiveComposerProjectPath != nil,
                        selectedSession: selectedSession,
                        projectSessions: projectSessions,
                        onCreateTask: { title, priority, statusValue in
                            onCreateTask(title, priority, statusValue)
                        },
                        onMoveTask: onMoveTask,
                        onLinkSelectedSession: onLinkSelectedSession,
                        onDeleteTask: onDeleteTask
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if composerProjectPath == nil {
                composerProjectPath = selectedProjectPath ?? projects.first?.path
            }
        }
        .onChange(of: selectedProjectPath) { _, newValue in
            if let newValue {
                composerProjectPath = newValue
            }
        }
    }

    private var projectsByPath: [String: StoredProject] {
        Dictionary(uniqueKeysWithValues: projects.map { ($0.path, $0) })
    }

    /// Path used by the composer when creating a task. In aggregate mode we
    /// fall back to the first project so the user can still add tasks
    /// without first switching scope.
    private var effectiveComposerProjectPath: String? {
        if let selectedProjectPath {
            return selectedProjectPath
        }
        return composerProjectPath ?? projects.first?.path
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            projectPicker

            Spacer(minLength: 12)

            HStack(spacing: 16) {
                metricLabel(value: scopedTasks.count, label: "kanban.tasks")
                metricLabel(value: linkedSessionCount, label: "kanban.sessions")
            }
        }
    }

    private var projectPicker: some View {
        Menu {
            Button {
                selectedProjectPath = nil
            } label: {
                HStack {
                    Text("kanban.all_projects")
                    if selectedProjectPath == nil {
                        Spacer()
                        Image(systemName: "checkmark")
                    }
                }
            }

            if !projects.isEmpty {
                Divider()
                ForEach(projects, id: \.path) { project in
                    Button {
                        selectedProjectPath = project.path
                    } label: {
                        HStack {
                            Text(project.displayName)
                            if selectedProjectPath == project.path {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(headerTitle)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.primary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var headerTitle: String {
        if let scopedProject {
            return scopedProject.displayName
        }
        return L10n.tr("kanban.all_projects")
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

    private var linkedSessionCount: Int {
        Set(scopedTasks.flatMap(\.linkedSessionIDs)).count
    }
}

private struct KanbanColumnView: View {
    let status: KanbanTaskStatus
    let tasks: [StoredKanbanTask]
    let showProjectName: Bool
    let projectsByPath: [String: StoredProject]
    /// Project path the inline composer will create tasks under. May be
    /// `nil` when there are no projects at all.
    let composerProjectPath: String?
    let canCompose: Bool
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
                            projectName: showProjectName ? projectsByPath[task.projectPath]?.displayName : nil,
                            projectSessions: projectSessions,
                            selectedSession: selectedSession,
                            onLinkSelectedSession: onLinkSelectedSession,
                            onDeleteTask: onDeleteTask
                        )
                        .draggable(KanbanTaskDragPayload(id: task.id))
                    }

                    if canCompose {
                        KanbanColumnComposerView(status: status, onCreateTask: onCreateTask)
                    }
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
    /// Non-nil only in aggregate ("all projects") mode — shown as a small
    /// badge on the card so the user can tell which project a task belongs
    /// to without switching scope.
    let projectName: String?
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
                if let projectName {
                    Label(projectName, systemImage: "folder")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                }

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
