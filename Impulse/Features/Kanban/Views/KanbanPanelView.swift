import AppKit
import SwiftUI

struct KanbanPanelView: View {
    let projects: [StoredProject]
    @Binding var selectedProjectPath: String?
    let tasks: [StoredKanbanTask]
    var onCreateTask: (_ projectPath: String, _ title: String, _ priority: KanbanTaskPriority, _ status: KanbanTaskStatus, _ labels: [String]) -> Void
    var onMoveTask: (StoredKanbanTask, KanbanTaskStatus) -> Void
    var onDeleteTask: (StoredKanbanTask) -> Void
    var onUpdateLabels: (StoredKanbanTask, [String]) -> Void

    private let columns: [KanbanTaskStatus] = [.plan, .inProgress, .done]

    @State private var composerProjectPath: String?
    @State private var activeLabelFilters: Set<String> = []
    @State private var showSettingsPopover = false

    private var scopedProject: StoredProject? {
        guard let path = selectedProjectPath else { return nil }
        return projects.first(where: { $0.path == path })
    }

    private var scopedTasks: [StoredKanbanTask] {
        let projectScoped = selectedProjectPath.map { path in
            tasks.filter { $0.projectPath == path }
        } ?? tasks

        guard !activeLabelFilters.isEmpty else { return projectScoped }
        return projectScoped.filter { task in
            !activeLabelFilters.isDisjoint(with: Set(task.labels))
        }
    }

    private var availableLabels: [String] {
        let projectScoped = selectedProjectPath.map { path in
            tasks.filter { $0.projectPath == path }
        } ?? tasks

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
                        onCreateTask: onCreateTask,
                        onMoveTask: onMoveTask,
                        onDeleteTask: onDeleteTask,
                        onUpdateLabels: onUpdateLabels
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            composerProjectPath = selectedProjectPath
        }
        .onChange(of: selectedProjectPath) { _, newValue in
            composerProjectPath = newValue
            activeLabelFilters = activeLabelFilters.intersection(Set(availableLabels))
        }
    }

    private var projectsByPath: [String: StoredProject] {
        Dictionary(uniqueKeysWithValues: projects.map { ($0.path, $0) })
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Spacer(minLength: 0)

            metricLabel(value: scopedTasks.count, label: "kanban.tasks")

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
        scopedProject?.displayName ?? L10n.tr("kanban.all_projects")
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
}

private struct KanbanColumnView: View {
    let status: KanbanTaskStatus
    let tasks: [StoredKanbanTask]
    let showProjectName: Bool
    let projectsByPath: [String: StoredProject]
    let availableProjects: [StoredProject]
    let isAggregateMode: Bool
    @Binding var composerProjectPath: String?
    let scopedProjectPath: String?
    let canCompose: Bool
    var onCreateTask: (_ projectPath: String, _ title: String, _ priority: KanbanTaskPriority, _ status: KanbanTaskStatus, _ labels: [String]) -> Void
    var onMoveTask: (StoredKanbanTask, KanbanTaskStatus) -> Void
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
                  let task = tasks.first(where: { $0.id == payload.id }) ?? findTask(byID: payload.id)
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

    private func findTask(byID id: String) -> StoredKanbanTask? { nil }
}

private struct KanbanColumnComposerView: View {
    let status: KanbanTaskStatus
    let availableProjects: [StoredProject]
    let showProjectPicker: Bool
    let scopedProjectPath: String?
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
    let projectName: String?
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
            isHovered = hovering
        }
        .contextMenu {
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
