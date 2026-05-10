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
    var onCreateTask: (_ projectPath: String, _ title: String, _ priority: KanbanTaskPriority, _ status: KanbanTaskStatus, _ labels: [String]) -> Void
    var onMoveTask: (StoredKanbanTask, KanbanTaskStatus) -> Void
    var onLinkSelectedSession: (StoredKanbanTask) -> Void
    var onDeleteTask: (StoredKanbanTask) -> Void
    var onUpdateLabels: (StoredKanbanTask, [String]) -> Void

    private let columns: [KanbanTaskStatus] = [.plan, .inProgress, .done]

    /// In aggregate mode, the composer needs to know which project a new
    /// task belongs to. `nil` means the user hasn't chosen one yet — the
    /// composer surfaces an explicit picker rather than silently defaulting
    /// to the first project.
    @State private var composerProjectPath: String?
    /// Labels currently applied as a filter (multi-select). Empty == no
    /// filter, all tasks shown.
    @State private var activeLabelFilters: Set<String> = []
    @State private var showSettingsPopover = false

    private var scopedProject: StoredProject? {
        guard let path = selectedProjectPath else { return nil }
        return projects.first(where: { $0.path == path })
    }

    private var scopedTasks: [StoredKanbanTask] {
        let projectScoped: [StoredKanbanTask]
        if let path = selectedProjectPath {
            projectScoped = tasks.filter { $0.projectPath == path }
        } else {
            projectScoped = tasks
        }
        guard !activeLabelFilters.isEmpty else { return projectScoped }
        return projectScoped.filter { task in
            !activeLabelFilters.isDisjoint(with: Set(task.labels))
        }
    }

    /// Distinct labels across the project-scoped task set (before label
    /// filtering). Drives the settings popover's filter list.
    private var availableLabels: [String] {
        let projectScoped: [StoredKanbanTask]
        if let path = selectedProjectPath {
            projectScoped = tasks.filter { $0.projectPath == path }
        } else {
            projectScoped = tasks
        }
        var seen = Set<String>()
        var ordered: [String] = []
        for task in projectScoped {
            for label in task.labels where !seen.contains(label) {
                seen.insert(label)
                ordered.append(label)
            }
        }
        return ordered.sorted()
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
                        availableProjects: projects,
                        isAggregateMode: selectedProjectPath == nil,
                        composerProjectPath: $composerProjectPath,
                        scopedProjectPath: selectedProjectPath,
                        canCompose: !projects.isEmpty,
                        selectedSession: selectedSession,
                        projectSessions: projectSessions,
                        onCreateTask: { projectPath, title, priority, statusValue, labels in
                            onCreateTask(projectPath, title, priority, statusValue, labels)
                        },
                        onMoveTask: onMoveTask,
                        onLinkSelectedSession: onLinkSelectedSession,
                        onDeleteTask: onDeleteTask,
                        onUpdateLabels: onUpdateLabels
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: selectedProjectPath) { _, newValue in
            // When user pins to a specific project, mirror it so the composer
            // selection stays in sync. Switching back to aggregate clears the
            // composer's choice — we don't want to silently inherit the last
            // scope.
            composerProjectPath = newValue
            // Drop filters that no longer apply to the new scope.
            activeLabelFilters = activeLabelFilters.intersection(Set(availableLabels))
        }
    }

    private var projectsByPath: [String: StoredProject] {
        Dictionary(uniqueKeysWithValues: projects.map { ($0.path, $0) })
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Spacer(minLength: 0)

            HStack(spacing: 16) {
                metricLabel(value: scopedTasks.count, label: "kanban.tasks")
                metricLabel(value: linkedSessionCount, label: "kanban.sessions")
            }

            settingsButton
        }
    }

    private var hasActiveFilter: Bool {
        !activeLabelFilters.isEmpty || selectedProjectPath != nil
    }

    private var settingsButton: some View {
        Button {
            showSettingsPopover.toggle()
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(hasActiveFilter ? .accentColor : .secondary)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(hasActiveFilter ? Color.accentColor.opacity(0.12) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help("kanban.settings")
        .popover(isPresented: $showSettingsPopover, arrowEdge: .top) {
            settingsPopover
        }
    }

    private var settingsPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            projectFilterSection

            Divider().opacity(0.5)

            HStack {
                Text("kanban.filter_by_labels")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if !activeLabelFilters.isEmpty {
                    Button("kanban.clear_filter") { activeLabelFilters.removeAll() }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
            }

            if availableLabels.isEmpty {
                Text("kanban.no_labels_yet")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(availableLabels, id: \.self) { label in
                            labelFilterRow(label)
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
        }
        .padding(14)
        .frame(width: 260, alignment: .leading)
    }

    private var projectFilterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("kanban.filter_by_project")
                .font(.system(size: 13, weight: .semibold))

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
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(headerTitle)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
    }

    private func labelFilterRow(_ label: String) -> some View {
        let isActive = activeLabelFilters.contains(label)
        return Button {
            if isActive {
                activeLabelFilters.remove(label)
            } else {
                activeLabelFilters.insert(label)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isActive ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundColor(isActive ? .accentColor : .secondary)
                Text(label)
                    .font(.system(size: 12.5))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
    /// Full list of projects — used by the composer's inline picker when in
    /// aggregate mode so the user can pick the destination project per task.
    let availableProjects: [StoredProject]
    /// True when the kanban is showing all projects. Drives whether the
    /// composer surfaces a project picker.
    let isAggregateMode: Bool
    /// Composer's selected destination project (binding so all four columns
    /// stay in sync).
    @Binding var composerProjectPath: String?
    /// When the user has scoped to a specific project, the composer uses
    /// that path directly and skips its own picker.
    let scopedProjectPath: String?
    let canCompose: Bool
    let selectedSession: StoredSession?
    let projectSessions: [StoredSession]
    var onCreateTask: (_ projectPath: String, _ title: String, _ priority: KanbanTaskPriority, _ status: KanbanTaskStatus, _ labels: [String]) -> Void
    var onMoveTask: (StoredKanbanTask, KanbanTaskStatus) -> Void
    var onLinkSelectedSession: (StoredKanbanTask) -> Void
    var onDeleteTask: (StoredKanbanTask) -> Void
    var onUpdateLabels: (StoredKanbanTask, [String]) -> Void

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
                            onDeleteTask: onDeleteTask,
                            onUpdateLabels: onUpdateLabels
                        )
                        .draggable(KanbanTaskDragPayload(id: task.id))
                    }

                    if canCompose {
                        KanbanColumnComposerView(
                            status: status,
                            availableProjects: availableProjects,
                            showProjectPicker: isAggregateMode,
                            scopedProjectPath: scopedProjectPath,
                            composerProjectPath: $composerProjectPath,
                            onCreateTask: onCreateTask
                        )
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
    let availableProjects: [StoredProject]
    /// True in aggregate ("All Projects") mode — composer surfaces an
    /// inline project picker and refuses to submit without a selection.
    let showProjectPicker: Bool
    /// When the kanban is scoped to a specific project, this carries that
    /// path so the composer can route tasks to it without a picker.
    let scopedProjectPath: String?
    /// Composer's current destination project in aggregate mode. Bound up
    /// so the choice persists across columns/expansions in one session.
    @Binding var composerProjectPath: String?
    var onCreateTask: (_ projectPath: String, _ title: String, _ priority: KanbanTaskPriority, _ status: KanbanTaskStatus, _ labels: [String]) -> Void

    @State private var isExpanded = false
    @State private var title = ""
    @State private var priority: KanbanTaskPriority = .medium
    @State private var labelDraft = ""
    @State private var labels: [String] = []
    @State private var isAddingLabel = false
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isLabelFieldFocused: Bool

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The project path the submit will commit to. Scoped mode wins; in
    /// aggregate mode we use the explicit picker selection.
    private var resolvedProjectPath: String? {
        scopedProjectPath ?? composerProjectPath
    }

    private var canSubmit: Bool {
        !trimmedTitle.isEmpty && resolvedProjectPath != nil
    }

    private var pickerLabel: String {
        if let path = composerProjectPath,
           let project = availableProjects.first(where: { $0.path == path }) {
            return project.displayName
        }
        return L10n.tr("kanban.select_project")
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

            if !labels.isEmpty {
                composerLabelChips
            }

            // Linear-style pill row: each metadata is its own capsule button.
            // Vertical stack so it fits any column width without truncation.
            VStack(alignment: .leading, spacing: 6) {
                if showProjectPicker {
                    projectPicker
                }
                priorityMenu
                labelAddPill
            }

            Divider().opacity(0.4)

            HStack(spacing: 6) {
                Spacer(minLength: 0)
                Button("common.cancel") { collapse() }
                    .controlSize(.small)
                    .buttonStyle(.borderless)
                Button("kanban.add_task") { submit() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!canSubmit)
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

    private var projectPicker: some View {
        Menu {
            ForEach(availableProjects, id: \.path) { project in
                Button {
                    composerProjectPath = project.path
                } label: {
                    HStack {
                        Text(project.displayName)
                        if composerProjectPath == project.path {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            pillLabel(
                systemImage: "folder",
                text: pickerLabel,
                isPlaceholder: composerProjectPath == nil
            )
        }
        .buttonStyle(.plain)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var priorityMenu: some View {
        Menu {
            ForEach(KanbanTaskPriority.allCases) { p in
                Button {
                    priority = p
                } label: {
                    HStack {
                        Text(p.localizedTitle)
                        if priority == p {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            pillLabel(
                systemImage: priorityIconName,
                text: priority.localizedTitle,
                isPlaceholder: false,
                tint: priority == .high ? Color(nsColor: .systemRed) : nil
            )
        }
        .buttonStyle(.plain)
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var priorityIconName: String {
        switch priority {
        case .low:    return "chevron.down"
        case .medium: return "minus"
        case .high:   return "exclamationmark"
        }
    }

    @ViewBuilder
    private var labelAddPill: some View {
        if isAddingLabel {
            TextField("kanban.add_label_placeholder", text: $labelDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .focused($isLabelFieldFocused)
                .onSubmit {
                    commitLabelDraft()
                    isAddingLabel = false
                }
                .onExitCommand {
                    labelDraft = ""
                    isAddingLabel = false
                }
                .fixedSize()
        } else {
            Button {
                isAddingLabel = true
                DispatchQueue.main.async { isLabelFieldFocused = true }
            } label: {
                pillLabel(systemImage: "tag", text: L10n.tr("kanban.add_label"), isPlaceholder: true)
            }
            .buttonStyle(.plain)
        }
    }

    /// Shared capsule label for pill buttons (project / priority / add label).
    /// `tint` overrides the foreground color for emphasis (e.g. high priority).
    private func pillLabel(systemImage: String, text: String, isPlaceholder: Bool, tint: Color? = nil) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10))
                .foregroundColor(tint ?? .secondary)
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(tint ?? (isPlaceholder ? .secondary : .primary.opacity(0.85)))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }

    private var composerLabelChips: some View {
        HStack(spacing: 4) {
            ForEach(labels, id: \.self) { label in
                HStack(spacing: 3) {
                    Text(label)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.primary.opacity(0.85))
                    Button {
                        labels.removeAll { $0 == label }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                )
            }
            Spacer()
        }
    }

    private func commitLabelDraft() {
        let trimmed = labelDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !labels.contains(trimmed) else {
            labelDraft = ""
            return
        }
        labels.append(trimmed)
        labelDraft = ""
    }

    private func submit() {
        commitLabelDraft()
        guard !trimmedTitle.isEmpty, let projectPath = resolvedProjectPath else { return }
        onCreateTask(projectPath, trimmedTitle, priority, status, labels)
        title = ""
        priority = .medium
        labels = []
        labelDraft = ""
        isAddingLabel = false
        isExpanded = false
        isTitleFocused = false
    }

    private func collapse() {
        title = ""
        priority = .medium
        labels = []
        labelDraft = ""
        isAddingLabel = false
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
    var onUpdateLabels: (StoredKanbanTask, [String]) -> Void

    @State private var isHovered = false
    @State private var labelDraft = ""
    @State private var isAddingLabel = false
    @FocusState private var isLabelFieldFocused: Bool

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

            if !task.labels.isEmpty || isAddingLabel || isHovered {
                labelStrip
            }

            HStack(spacing: 10) {
                if let projectName {
                    Label(projectName, systemImage: "folder")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(0)
                }

                if task.priority != .medium {
                    Text(task.priority.localizedTitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(priorityForeground)
                        .lineLimit(1)
                        .fixedSize()
                        .layoutPriority(2)
                }

                if !task.linkedSessionIDs.isEmpty {
                    Label(linkedSessionsLabel, systemImage: "link")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                }

                Spacer(minLength: 0)

                Text(task.updatedAt, format: .dateTime.month().day())
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .layoutPriority(2)
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

    private var labelStrip: some View {
        HStack(spacing: 4) {
            ForEach(task.labels, id: \.self) { label in
                HStack(spacing: 3) {
                    Text(label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.primary.opacity(0.78))
                    if isHovered {
                        Button {
                            removeLabel(label)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 7, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.secondary.opacity(0.1))
                )
            }

            if isAddingLabel {
                TextField("kanban.add_label_placeholder", text: $labelDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10.5))
                    .frame(width: 80)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    .focused($isLabelFieldFocused)
                    .onSubmit { commitLabelDraft() }
                    .onExitCommand { cancelLabelDraft() }
            } else if isHovered {
                Button {
                    isAddingLabel = true
                    DispatchQueue.main.async { isLabelFieldFocused = true }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
    }

    private func commitLabelDraft() {
        let trimmed = labelDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            cancelLabelDraft()
            return
        }
        var current = task.labels
        if !current.contains(trimmed) {
            current.append(trimmed)
            onUpdateLabels(task, current)
        }
        labelDraft = ""
        isAddingLabel = false
        isLabelFieldFocused = false
    }

    private func cancelLabelDraft() {
        labelDraft = ""
        isAddingLabel = false
        isLabelFieldFocused = false
    }

    private func removeLabel(_ label: String) {
        var current = task.labels
        current.removeAll { $0 == label }
        onUpdateLabels(task, current)
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
        case .plan:       return L10n.tr("kanban.status.plan")
        case .inProgress: return L10n.tr("kanban.status.in_progress")
        case .done:       return L10n.tr("kanban.status.done")
        }
    }

    var localizedEmptyHint: String {
        switch self {
        case .plan:       return L10n.tr("kanban.status.plan.empty_hint")
        case .inProgress: return L10n.tr("kanban.status.in_progress.empty_hint")
        case .done:       return L10n.tr("kanban.status.done.empty_hint")
        }
    }

    /// Muted status accents — Linear-style. Only used as a 6pt dot in the
    /// column header; the rest of the chrome stays monochrome.
    var tintColor: Color {
        switch self {
        case .plan:       return Color.secondary
        case .inProgress: return Color(nsColor: .systemBlue)
        case .done:       return Color(nsColor: .systemGreen)
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
