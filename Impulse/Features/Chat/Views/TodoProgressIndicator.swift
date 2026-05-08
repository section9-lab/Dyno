import SwiftHarnessAgent
import SwiftUI

/// Toolbar affordance that surfaces the focused session's todo list.
///
/// Renders as a compact pill: completed/total count + the truncated name of
/// the current `in_progress` task, with a thin progress ring to the left.
/// Tapping opens a popover that lists every phase and task with status icons.
///
/// Hidden when there are no phases — sessions that never use the
/// `todo_write` tool see no toolbar clutter.
struct TodoProgressIndicator: View {
    @ObservedObject var sessionAgent: SessionAgent

    @State private var showPopover: Bool = false

    var body: some View {
        if sessionAgent.todoPhases.isEmpty {
            EmptyView()
        } else {
            Button {
                showPopover.toggle()
            } label: {
                HStack(spacing: 6) {
                    TodoProgressRing(percent: completionPercent)
                        .frame(width: 14, height: 14)

                    Text(progressLabel)
                        .chatFont(.footnote, weight: .medium, design: .monospaced)
                        .foregroundColor(.primary.opacity(0.85))

                    if let active = currentInProgressTitle {
                        Text(active)
                            .chatFont(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 180, alignment: .leading)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.10))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(helpText)
            .popover(isPresented: $showPopover, arrowEdge: .top) {
                TodoProgressPopover(phases: sessionAgent.todoPhases)
            }
        }
    }

    private var totalTasks: Int {
        sessionAgent.todoPhases.reduce(0) { $0 + $1.tasks.count }
    }

    private var completedTasks: Int {
        sessionAgent.todoPhases.reduce(0) { acc, phase in
            acc + phase.tasks.filter { $0.status == .completed }.count
        }
    }

    private var completionPercent: Double {
        guard totalTasks > 0 else { return 0 }
        return Double(completedTasks) / Double(totalTasks)
    }

    private var progressLabel: String {
        "\(completedTasks)/\(totalTasks)"
    }

    private var currentInProgressTitle: String? {
        for phase in sessionAgent.todoPhases {
            if let task = phase.tasks.first(where: { $0.status == .inProgress }) {
                return task.content
            }
        }
        return nil
    }

    private var helpText: String {
        if let current = currentInProgressTitle {
            return "Todos: \(progressLabel) — \(current)"
        }
        return "Todos: \(progressLabel)"
    }
}

// MARK: - Internals

private struct TodoProgressRing: View {
    let percent: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.20), lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(0.001, min(1.0, percent)))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.25), value: percent)
        }
    }
}

private struct TodoProgressPopover: View {
    let phases: [TodoPhase]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(phases.enumerated()), id: \.element.name) { _, phase in
                    PhaseSection(phase: phase)
                }
            }
            .padding(16)
        }
        .frame(minWidth: 280, idealWidth: 340, maxWidth: 420, minHeight: 120, maxHeight: 480)
    }
}

private struct PhaseSection: View {
    let phase: TodoPhase

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(phase.name)
                    .chatFont(.body, weight: .semibold)
                    .foregroundColor(.primary)
                Spacer(minLength: 0)
                Text("\(completedCount)/\(phase.tasks.count)")
                    .chatFont(.footnote, design: .monospaced)
                    .foregroundColor(.secondary)
            }

            ForEach(Array(phase.tasks.enumerated()), id: \.offset) { _, task in
                TaskRow(task: task)
            }
        }
    }

    private var completedCount: Int {
        phase.tasks.filter { $0.status == .completed }.count
    }
}

private struct TaskRow: View {
    let task: TodoItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(iconColor)
                .frame(width: 14)
            Text(task.content)
                .chatFont(.footnote)
                .foregroundColor(textColor)
                .strikethrough(task.status == .completed || task.status == .abandoned, color: .secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var iconName: String {
        switch task.status {
        case .pending: return "circle"
        case .inProgress: return "play.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .abandoned: return "minus.circle"
        }
    }

    private var iconColor: Color {
        switch task.status {
        case .pending: return .secondary.opacity(0.6)
        case .inProgress: return .accentColor
        case .completed: return .green
        case .abandoned: return .secondary.opacity(0.5)
        }
    }

    private var textColor: Color {
        switch task.status {
        case .pending: return .primary.opacity(0.85)
        case .inProgress: return .primary
        case .completed: return .secondary
        case .abandoned: return .secondary
        }
    }
}
