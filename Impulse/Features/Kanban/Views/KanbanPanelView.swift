import AppKit
import SwiftUI

struct KanbanPanelView: View {
    let project: ChatProject?
    let selectedSession: ChatSession?
    let tasks: [KanbanTaskSnapshot]
    @Binding var newTaskTitle: String
    @Binding var newTaskPriority: KanbanTaskPriority
    var onCreateTask: () -> Void
    var onMoveTask: (KanbanTaskSnapshot, KanbanTaskStatus) -> Void
    var onLinkSelectedSession: (KanbanTaskSnapshot) -> Void
    var onDeleteTask: (KanbanTaskSnapshot) -> Void

    private let columns = KanbanTaskStatus.allCases
    private let panelCornerRadius: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            composer

            if let project {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(columns) { status in
                        KanbanColumnView(
                            status: status,
                            tasks: tasks.filter { $0.status == status },
                            project: project,
                            selectedSession: selectedSession,
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
                    Label("Project Board", systemImage: "square.grid.3x3.topleft.filled")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)

                    Text(project?.name ?? "No project selected")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.primary)

                    Text(project == nil ? "Select a project to organize work." : "Tasks stay attached to the project and can link to one or more sessions.")
                        .font(.system(size: 12.5))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 16)

                VStack(alignment: .trailing, spacing: 8) {
                    if let selectedSession {
                        Label(selectedSession.title, systemImage: "bubble.left.and.bubble.right")
                            .lineLimit(1)
                            .font(.system(size: 11.5, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.75))
                            )
                    }

                    HStack(spacing: 8) {
                        headerMetric(title: "Tasks", value: "\(tasks.count)")
                        headerMetric(title: "Sessions", value: "\(linkedSessionCount)")
                    }
                }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)

                TextField("Add a task for this project", text: $newTaskTitle)
                    .textFieldStyle(.plain)
                    .onSubmit(onCreateTask)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )

            Picker("Priority", selection: $newTaskPriority) {
                ForEach(KanbanTaskPriority.allCases) { priority in
                    Text(priority.title).tag(priority)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)

            Button("Add Task") {
                onCreateTask()
            }
            .buttonStyle(.borderedProminent)
            .disabled(project == nil || newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.55))
        )
    }

    private var emptyState: some View {
        VStack(alignment: .center, spacing: 12) {
            Spacer()
            Image(systemName: "rectangle.3.group.bubble.left")
                .font(.system(size: 30, weight: .medium))
                .foregroundColor(.secondary)
            Text("Select a project to open its board")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
            Text("Tasks are organized at the project level and can stay linked to multiple sessions.")
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

    private func headerMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minWidth: 68, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.72))
        )
    }
}

private struct KanbanColumnView: View {
    let status: KanbanTaskStatus
    let tasks: [KanbanTaskSnapshot]
    let project: ChatProject
    let selectedSession: ChatSession?
    var onMoveTask: (KanbanTaskSnapshot, KanbanTaskStatus) -> Void
    var onLinkSelectedSession: (KanbanTaskSnapshot) -> Void
    var onDeleteTask: (KanbanTaskSnapshot) -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(status.tintColor)
                            .frame(width: 8, height: 8)

                        Text(status.title)
                            .font(.system(size: 15, weight: .semibold))
                    }

                    Text(status.subtitle)
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
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
                                project: project,
                                selectedSession: selectedSession,
                                onLinkSelectedSession: onLinkSelectedSession,
                                onDeleteTask: onDeleteTask
                            )
                            .draggable(task)
                        }
                    }
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
        .dropDestination(for: KanbanTaskSnapshot.self) { droppedTasks, _ in
            guard let task = droppedTasks.first else { return false }
            onMoveTask(task, status)
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }

    private var emptyDropState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Drop task here")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(.secondary)
            Text(status.emptyHint)
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

private struct KanbanTaskCardView: View {
    let task: KanbanTaskSnapshot
    let project: ChatProject
    let selectedSession: ChatSession?
    var onLinkSelectedSession: (KanbanTaskSnapshot) -> Void
    var onDeleteTask: (KanbanTaskSnapshot) -> Void

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
                    Button(isLinkedToSelectedSession ? "Session Linked" : "Link Current Session") {
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
                Button("Link Current Session", systemImage: "link.badge.plus") {
                    onLinkSelectedSession(task)
                }
            }
            Button("Delete Task", systemImage: "trash", role: .destructive) {
                onDeleteTask(task)
            }
        }
    }

    private var primarySessionTitle: String? {
        guard let primarySessionID = task.primarySessionID else { return nil }
        return project.sessions.first(where: { $0.id == primarySessionID })?.title
    }

    private var isLinkedToSelectedSession: Bool {
        guard let selectedSession else { return false }
        return task.linkedSessionIDs.contains(selectedSession.id)
    }

    private var linkedSessionsLabel: String {
        task.linkedSessionIDs.count == 1 ? "1 session" : "\(task.linkedSessionIDs.count) sessions"
    }

    private var priorityBadge: some View {
        Text(task.priority.title)
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
        case .low:
            return Color(nsColor: .systemBlue)
        case .medium:
            return Color(nsColor: .systemOrange)
        case .high:
            return Color(nsColor: .systemRed)
        }
    }
}

private extension KanbanTaskStatus {
    var subtitle: String {
        switch self {
        case .plan:
            return "Scoped and ready to pick up."
        case .progress:
            return "Work currently moving forward."
        case .done:
            return "Completed work kept for reference."
        }
    }

    var emptyHint: String {
        switch self {
        case .plan:
            return "New project tasks start here."
        case .progress:
            return "Move active tasks here while they are underway."
        case .done:
            return "Drop finished tasks here to keep the board tidy."
        }
    }

    var tintColor: Color {
        switch self {
        case .plan:
            return Color(nsColor: .systemBlue)
        case .progress:
            return Color(nsColor: .systemOrange)
        case .done:
            return Color(nsColor: .systemGreen)
        }
    }
}
