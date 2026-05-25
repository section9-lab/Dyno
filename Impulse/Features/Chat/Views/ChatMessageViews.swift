import SwiftHarnessAgent
import AppKit
import MarkdownUI
import SwiftUI

struct ChatWelcomeHeader: View {
    var body: some View {
        Text("chat.welcome")
            .chatFont(.title, weight: .semibold)
            .foregroundColor(.primary.opacity(0.88))
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
            .padding(.bottom, 14)
    }
}

struct TypingIndicatorView: View {
    @Environment(\.colorScheme) private var colorScheme

    @State private var animating = false
    private let dotSize: CGFloat = 9
    private let dotTravel: CGFloat = 2.5

    var body: some View {
        HStack {
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.gray.opacity(0.6))
                        .frame(width: dotSize, height: dotSize)
                        .scaleEffect(animating ? 1.0 : 0.82)
                        .offset(y: animating ? -dotTravel : dotTravel)
                        .opacity(animating ? 0.95 : 0.45)
                        .animation(
                            .easeInOut(duration: 0.55)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.15),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(
                Capsule().fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.white.opacity(0.55))
            )
            .clipShape(Capsule())
            Spacer()
        }
        .padding(.horizontal, 56)
        .onAppear { animating = true }
    }
}

struct MessageView: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var themeManager: ThemeManager

    let message: StoredMessage

    var body: some View {
        if message.isUser {
            HStack {
                Spacer(minLength: 80)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(message.content)
                        .chatFont(.body, weight: .semibold)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 16)
                        .background(userMessageBackground)
                        .foregroundColor(.primary)
                        .clipShape(Capsule())

                    // Mirror layout for right-aligned user bubble: timestamp on the
                    // outer left, action icons sit closer to the bubble edge.
                    HStack(spacing: 6) {
                        Text(message.timestamp, format: .dateTime.hour().minute())
                            .chatFont(.footnote)
                            .foregroundColor(.secondary)

                        CopyMessageButton(text: message.content)
                    }
                }
            }
            .padding(.horizontal, 56)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Markdown(message.content)
                    .markdownTextStyle {
                        FontSize(14 * themeManager.textSize.multiplier)
                    }
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                // Action icons first, timestamp follows — matches the reference
                // ChatGPT/Claude pattern where the copy affordance sits closest
                // to the message it acts on.
                HStack(spacing: 4) {
                    CopyMessageButton(text: message.content)

                    Text(message.timestamp, format: .dateTime.hour().minute())
                        .chatFont(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 56)
        }
    }

    private var userMessageBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.075) : Color.white.opacity(0.55)
    }
}

/// Outlined icon button placed in the message action row, modelled after the
/// ChatGPT/Claude pattern: a 26×26 hit area with a 12pt SF Symbol, a soft
/// rounded hover background, and a brief ✓ confirmation when pressed.
struct CopyMessageButton: View {
    let text: String

    @State private var didCopy: Bool = false
    @State private var resetTask: Task<Void, Never>? = nil
    @State private var isHovering: Bool = false

    var body: some View {
        Button(action: copy) {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(iconColor)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovering ? Color.secondary.opacity(0.12) : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(L10n.tr(didCopy ? "chat.message.copied" : "chat.message.copy"))
        .onHover { hovering in
            isHovering = hovering
        }
        .onDisappear {
            resetTask?.cancel()
        }
        .animation(.easeInOut(duration: 0.18), value: didCopy)
        .animation(.easeInOut(duration: 0.12), value: isHovering)
    }

    private var iconColor: Color {
        if didCopy {
            return .secondary
        }
        return isHovering ? .primary.opacity(0.85) : .secondary.opacity(0.7)
    }

    private func copy() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        didCopy = true

        resetTask?.cancel()
        resetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if !Task.isCancelled {
                didCopy = false
            }
        }
    }
}

/// Standalone row that displays a persisted reasoning trace as a collapsible
/// "Thinking" pane. Rendered as its own `ChatRow.reasoning` entry so it can
/// sit *before* the tool group that ran on behalf of the same assistant turn,
/// keeping the visual order "thinking → tools → answer". Default collapsed.
struct PersistedReasoningRow: View {
    let text: String

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.secondary)
                    Text("Thinking")
                        .chatFont(.body)
                        .foregroundColor(.secondary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.6))
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(text)
                    .chatFont(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 56)
    }
}

struct ToolExecutionMessageView: View {
    let execution: AgentToolExecution
    var isLast: Bool = true
    /// `true` only for the row that is currently the focus of execution
    /// (the last entry whose status is `.running`). Earlier completed
    /// rows pass `false` so they don't pulse alongside the live one.
    var isActive: Bool = true

    var body: some View {
        if execution.toolName == "task" {
            TaskFanoutRow(
                model: TaskFanoutModelBuilder.fromLive(execution),
                isLast: isLast,
                isActive: isActive
            )
        } else {
            ToolTimelineRow(
                toolName: execution.toolName,
                status: execution.status,
                summary: execution.summary,
                output: execution.output,
                isLast: isLast,
                isActive: isActive
            )
        }
    }
}

struct PersistedToolExecutionMessageView: View {
    let run: StoredToolRun
    var isLast: Bool = true

    var body: some View {
        if run.toolName == "task" {
            TaskFanoutRow(
                model: TaskFanoutModelBuilder.fromPersisted(run),
                isLast: isLast,
                isActive: false
            )
        } else {
            ToolTimelineRow(
                toolName: run.toolName,
                status: run.status == "success" ? .success : (run.status == "failed" ? .failed : .running),
                summary: run.summary,
                output: run.output,
                isLast: isLast,
                isActive: false
            )
        }
    }
}

// MARK: - Single persisted tool execution row

// Persisted tool runs are rendered as individual rows in the chat scroll
// area, in their original emission order. Each row owns its own status
// icon (success / failed / running) so the per-tool "done" state is
// visible immediately without a group-level summary card.

private struct ToolTimelineRow: View {
    let toolName: String
    let status: AgentToolExecutionStatus
    let summary: String
    let output: String
    let isLast: Bool
    /// Whether this row is the currently-focused execution. Controls the
    /// pulse animation: only the active row pulses, even if multiple rows
    /// happen to share `.running` status (rare, but possible during retries
    /// or parallel tool calls).
    let isActive: Bool

    @State private var isExpanded = false
    @State private var pulseOn = false

    private var shouldPulse: Bool { status == .running && isActive }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Left rail: icon + connector line.
            // Icon stays neutral and static even while running — the only
            // motion cue lives on the title text below, so the timeline rail
            // reads as a calm structural element.
            VStack(spacing: 0) {
                ZStack {
                    Image(systemName: iconName)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(iconColor)
                }
                .frame(width: 22, height: 22)

                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 22)

            // Right side: title + expandable detail
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        // Title text holds the only motion: a gentle opacity
                        // pulse while the tool is running. Color stays
                        // constant so it never shifts hue on status change.
                        Text(titleText)
                            .chatFont(.body)
                            .foregroundColor(.primary.opacity(0.92))
                            .opacity(shouldPulse && pulseOn ? 0.45 : 1.0)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.6))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
                .buttonStyle(.plain)

                // Subtitle chip — Script / Result / Request style
                if let chip = chipText {
                    Text(chip)
                        .chatFont(.footnote, design: .monospaced)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(chipBackground)
                        .foregroundColor(chipForeground)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }

                if isExpanded {
                    ToolDetailPanel(toolName: toolName, summary: summary, output: output, status: status)
                        .padding(.top, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.bottom, isLast ? 0 : 14)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 56)
        .onAppear {
            if shouldPulse { startPulse() }
        }
        .onChange(of: shouldPulse) { _, newValue in
            if newValue {
                startPulse()
            } else {
                pulseOn = false
            }
        }
    }

    private func startPulse() {
        pulseOn = false
        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
            pulseOn = true
        }
    }

    private var iconName: String {
        switch toolName {
        case "read": return "doc.text"
        case "write": return "square.and.pencil"
        case "edit": return "pencil.line"
        case "bash": return "terminal"
        case "task": return "square.stack.3d.up"
        case "todo_write": return "checklist"
        default: return "wrench.and.screwdriver"
        }
    }

    private var iconColor: Color {
        // Icon color is intentionally status-agnostic for the running state:
        // we don't tint it the accent color while a tool is in flight, since
        // a colored "badge" can read like an alert. Failure remains red so
        // problems are still glanceable.
        switch status {
        case .running, .success: return .primary.opacity(0.75)
        case .failed: return .red
        }
    }

    private var titleText: String {
        switch toolName {
        case "read":
            return "Read \(filenameOrFallback)"
        case "write":
            return "Wrote \(filenameOrFallback)"
        case "edit":
            return "Edited \(filenameOrFallback)"
        case "bash":
            switch status {
            case .running: return "Running command"
            case .success: return "Ran command"
            case .failed:  return "Command failed"
            }
        case "task":
            // Summary is "<agentID> × <count>" (set in
            // SessionAgent.buildToolSummary). Parse it back into the two
            // pieces so the title reads naturally.
            let (count, agentID) = parseTaskSummary()
            switch status {
            case .running:
                return L10n.tr("tool.task.running_n", count, agentID)
            case .success:
                return L10n.tr("tool.task.ran_n", count, agentID)
            case .failed:
                return L10n.tr("tool.task.failed", agentID)
            }
        case "todo_write":
            switch status {
            case .running: return L10n.tr("tool.todo_write.running")
            case .success: return L10n.tr("tool.todo_write.success")
            case .failed:  return L10n.tr("tool.todo_write.failed")
            }
        default:
            return toolName.capitalized
        }
    }

    /// Parses `summary` strings of the form "<agentID> × <count>" into
    /// (count, agentID). Falls back to (0, "subagent") on a malformed
    /// summary so the row still renders something sensible.
    private func parseTaskSummary() -> (count: Int, agentID: String) {
        let parts = summary.components(separatedBy: " × ")
        guard parts.count == 2,
              let count = Int(parts[1].trimmingCharacters(in: .whitespaces))
        else {
            return (0, "subagent")
        }
        return (count, parts[0].trimmingCharacters(in: .whitespaces))
    }

    private var filenameOrFallback: String {
        // Summary for file ops is "<path> (<filename>)"; pull filename if present.
        if let open = summary.lastIndex(of: "("),
           let close = summary.lastIndex(of: ")"),
           open < close {
            let start = summary.index(after: open)
            return String(summary[start..<close])
        }
        if !summary.isEmpty {
            return URL(fileURLWithPath: summary).lastPathComponent
        }
        return ""
    }

    private var chipText: String? {
        switch toolName {
        case "bash":
            // The terminal icon already says "this is a shell command" —
            // a "Script" chip on top of that is just visual noise.
            return nil
        case "task":
            return L10n.tr("tool.task.chip")
        case "read", "write", "edit":
            return nil
        default:
            return nil
        }
    }

    private var chipBackground: Color {
        // Running state shares the neutral look with success — the title text
        // pulse already conveys "in progress". Red is reserved for failure so
        // it still pops as an actionable alert.
        switch status {
        case .running, .success: return Color.secondary.opacity(0.12)
        case .failed: return Color.red.opacity(0.18)
        }
    }

    private var chipForeground: Color {
        switch status {
        case .running, .success: return .secondary
        case .failed: return .red
        }
    }
}

private struct ToolDetailPanel: View {
    let toolName: String
    let summary: String
    let output: String
    let status: AgentToolExecutionStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Argument / target line
            if !summary.isEmpty {
                argumentSection
            }

            // Output
            if status != .running {
                Divider().opacity(0.4)
                outputSection
            } else {
                Text(L10n.tr("tool.no_output"))
                    .chatFont(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var argumentSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(argumentLabel)
                .chatFont(.footnote, weight: .semibold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            Text(argumentValue)
                .chatFont(.caption, design: argumentMonospaced ? .monospaced : .default)
                .foregroundColor(.primary.opacity(0.85))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(outputLabel)
                .chatFont(.footnote, weight: .semibold)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let display = trimmed.isEmpty ? L10n.tr("tool.no_output") : trimmed
            ScrollView {
                Text(display)
                    .chatFont(.caption, design: .monospaced)
                    .foregroundColor(.primary.opacity(0.8))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 240)
        }
    }

    private var argumentLabel: String {
        switch toolName {
        case "bash": return "Command"
        case "read": return "Path"
        case "write": return "Path"
        case "edit": return "Path"
        default: return "Input"
        }
    }

    private var argumentValue: String {
        if toolName == "bash" { return summary }
        if let parenIndex = summary.lastIndex(of: "(") {
            let pathPart = summary[..<parenIndex].trimmingCharacters(in: .whitespaces)
            return String(pathPart)
        }
        return summary
    }

    private var argumentMonospaced: Bool {
        switch toolName {
        case "bash", "read", "write", "edit": return true
        default: return false
        }
    }

    private var outputLabel: String {
        toolName == "bash" ? "Result" : "Output"
    }
}

// MARK: - Task subagent output rendering

/// One per-task block parsed from the joined output of a `task` tool call.
/// The SDK formats each subagent result as:
///
///     ## Task <id> (<agentID>) — success|failed
///     steps: N
///     [error: ...]
///
///     <output>
///
/// We split that back into structured pieces so the detail panel can show
/// each subagent's result as its own card, with success/failure tinting.
struct TaskOutputBlock {
    let id: String
    let agentID: String
    let success: Bool
    let steps: Int
    let error: String?
    let output: String
}

enum TaskOutputParser {
    static func parse(_ raw: String) -> [TaskOutputBlock] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.hasPrefix("## Task ") else { return [] }

        // Split on lines that begin with "## Task ". Keep the prefix on the
        // resulting block so we can re-parse the header line.
        var blocks: [TaskOutputBlock] = []
        var currentLines: [String] = []
        for line in trimmed.components(separatedBy: "\n") {
            if line.hasPrefix("## Task ") {
                if !currentLines.isEmpty {
                    if let block = parseBlock(currentLines) {
                        blocks.append(block)
                    }
                    currentLines.removeAll(keepingCapacity: true)
                }
            }
            currentLines.append(line)
        }
        if !currentLines.isEmpty, let block = parseBlock(currentLines) {
            blocks.append(block)
        }
        return blocks
    }

    private static func parseBlock(_ lines: [String]) -> TaskOutputBlock? {
        guard let header = lines.first, header.hasPrefix("## Task ") else { return nil }
        // Header: "## Task <id> (<agent>) — success|failed"
        let stripped = String(header.dropFirst("## Task ".count))
        // Split on " — "
        let dashSep = " — "
        guard let dashRange = stripped.range(of: dashSep) else { return nil }
        let idAgent = stripped[..<dashRange.lowerBound].trimmingCharacters(in: .whitespaces)
        let statusPart = stripped[dashRange.upperBound...].trimmingCharacters(in: .whitespaces)
        let success = (statusPart == "success")

        // idAgent: "<id> (<agent>)"
        let id: String
        let agentID: String
        if let parenStart = idAgent.firstIndex(of: "("),
           let parenEnd = idAgent.firstIndex(of: ")"),
           parenStart < parenEnd {
            id = idAgent[..<parenStart].trimmingCharacters(in: .whitespaces)
            let inside = idAgent.index(after: parenStart)..<parenEnd
            agentID = String(idAgent[inside]).trimmingCharacters(in: .whitespaces)
        } else {
            id = idAgent
            agentID = ""
        }

        var steps = 0
        var error: String?
        var bodyStart = 1
        for (idx, line) in lines.enumerated().dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("steps: ") {
                steps = Int(trimmed.dropFirst("steps: ".count)) ?? 0
                bodyStart = idx + 1
            } else if trimmed.hasPrefix("error: ") {
                error = String(trimmed.dropFirst("error: ".count))
                bodyStart = idx + 1
            } else if trimmed.isEmpty {
                bodyStart = idx + 1
            } else {
                break
            }
        }
        let body = lines.dropFirst(bodyStart).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return TaskOutputBlock(id: id, agentID: agentID, success: success, steps: steps, error: error, output: body)
    }
}

struct TaskOutputCard: View {
    let block: TaskOutputBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: block.success ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundColor(block.success ? .green : .red)
                    .font(.system(size: 12))
                Text(block.id)
                    .chatFont(.footnote, weight: .semibold)
                    .foregroundColor(.primary.opacity(0.9))
                if !block.agentID.isEmpty {
                    Text(block.agentID)
                        .chatFont(.caption, design: .monospaced)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
                Text("steps: \(block.steps)")
                    .chatFont(.caption, design: .monospaced)
                    .foregroundColor(.secondary)
            }

            if let error = block.error, !error.isEmpty {
                Text(error)
                    .chatFont(.caption)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            if !block.output.isEmpty {
                Text(block.output)
                    .chatFont(.caption)
                    .foregroundColor(.primary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.06))
        )
    }
}

// MARK: - Task fanout row (parallel subagents)

/// One inner tool call inside a single subagent — used by both the live
/// (in-flight) and persisted (reload) rendering paths.
struct TaskFanoutInnerTool: Identifiable, Equatable {
    let id: String
    let toolName: String
    let status: AgentToolExecutionStatus
    let summary: String
    let output: String
}

/// One parallel subagent task within a fanout. The merged shape both the
/// live `AgentToolExecution.subagentLive` and the persisted
/// `argumentsJSON` + `StoredSubagentToolRun` + parsed output blocks get
/// flattened into.
struct TaskFanoutTaskEntry: Identifiable, Equatable {
    let id: String
    let description: String
    let agentID: String
    let status: AgentToolExecutionStatus
    let steps: Int
    let output: String
    let error: String?
    let innerTools: [TaskFanoutInnerTool]
}

/// Top-level model handed to `TaskFanoutRow`. Carries the agent label,
/// an aggregate status for the whole batch, and the per-task entries
/// in their original order.
struct TaskFanoutModel: Equatable {
    let agentLabel: String
    let overallStatus: AgentToolExecutionStatus
    let entries: [TaskFanoutTaskEntry]
}

/// Builds a `TaskFanoutModel` from either a live `AgentToolExecution`
/// or a reloaded `StoredToolRun`. The same row renderer consumes either.
enum TaskFanoutModelBuilder {
    /// Live path: read straight off `AgentToolExecution.subagentLive`.
    /// Entries may be partial (no output yet) while the batch is running.
    static func fromLive(_ exec: AgentToolExecution) -> TaskFanoutModel {
        let entries: [TaskFanoutTaskEntry] = exec.subagentLive.map { task in
            TaskFanoutTaskEntry(
                id: task.id,
                description: task.description,
                agentID: task.agentID,
                status: task.status,
                steps: task.steps,
                output: task.output,
                error: task.error,
                innerTools: task.innerTools.map {
                    TaskFanoutInnerTool(
                        id: $0.id,
                        toolName: $0.toolName,
                        status: $0.status,
                        summary: $0.summary,
                        output: $0.output
                    )
                }
            )
        }
        let agentLabel = entries.first?.agentID ?? agentLabelFromSummary(exec.summary)
        return TaskFanoutModel(
            agentLabel: agentLabel,
            overallStatus: exec.status,
            entries: entries
        )
    }

    /// Persisted path: merge per-task descriptions from `argumentsJSON`,
    /// inner tool runs from `StoredSubagentToolRun`s, and final status
    /// from `TaskOutputParser` blocks. Any data we can't recover falls
    /// back to neutral defaults so the row still renders.
    static func fromPersisted(_ run: StoredToolRun) -> TaskFanoutModel {
        // Step 1: parse arguments JSON for per-task description + agent.
        let (argAgent, argTasks) = parseArguments(run.argumentsJSON)
        // Step 2: parse final output for per-task success/failure/steps.
        let blocks = TaskOutputParser.parse(run.output)
        let blocksByID: [String: TaskOutputBlock] = Dictionary(
            uniqueKeysWithValues: blocks.map { ($0.id, $0) }
        )
        // Step 3: group inner tool runs by their subagentTaskID.
        let innerByTask: [String: [StoredSubagentToolRun]] = Dictionary(
            grouping: run.subagentRuns.sorted { $0.timestamp < $1.timestamp },
            by: { $0.subagentTaskID }
        )

        // Determine the iteration order. Prefer arguments-JSON order (matches
        // what the model dispatched); fall back to output blocks; fall back
        // to inner-run grouping keys.
        let orderedIDs: [String]
        if !argTasks.isEmpty {
            orderedIDs = argTasks.map(\.id)
        } else if !blocks.isEmpty {
            orderedIDs = blocks.map(\.id)
        } else {
            orderedIDs = Array(innerByTask.keys)
        }

        var entries: [TaskFanoutTaskEntry] = []
        for id in orderedIDs {
            let description = argTasks.first(where: { $0.id == id })?.description ?? ""
            let block = blocksByID[id]
            let agentID = block?.agentID ?? argAgent ?? ""
            let status: AgentToolExecutionStatus
            if let block {
                status = block.success ? .success : .failed
            } else {
                // No final block yet — treat as running (this row was
                // persisted mid-flight, which currently shouldn't happen
                // because persistence runs after the turn finishes).
                status = .running
            }
            let inner = (innerByTask[id] ?? []).map { row in
                TaskFanoutInnerTool(
                    id: row.id,
                    toolName: row.toolName,
                    status: AgentToolExecutionStatus(rawValue: row.status) ?? .success,
                    summary: row.summary,
                    output: row.output
                )
            }
            entries.append(TaskFanoutTaskEntry(
                id: id,
                description: description,
                agentID: agentID,
                status: status,
                steps: block?.steps ?? 0,
                output: block?.output ?? "",
                error: block?.error,
                innerTools: inner
            ))
        }

        let overall: AgentToolExecutionStatus
        switch run.status {
        case "success": overall = .success
        case "failed":  overall = .failed
        default:        overall = .running
        }
        let agentLabel = argAgent ?? entries.first?.agentID ?? agentLabelFromSummary(run.summary)
        return TaskFanoutModel(
            agentLabel: agentLabel,
            overallStatus: overall,
            entries: entries
        )
    }

    private struct ArgTask: Equatable {
        let id: String
        let description: String
    }

    /// Extract `agent` + the per-task `[{id, description}]` list from the
    /// JSON arguments captured at `toolStarted` time. Returns `(nil, [])`
    /// for legacy rows that pre-date the `argumentsJSON` field.
    private static func parseArguments(_ argumentsJSON: String?) -> (String?, [ArgTask]) {
        guard let argumentsJSON,
              let data = argumentsJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return (nil, []) }
        let agent = obj["agent"] as? String
        let rawTasks = (obj["tasks"] as? [[String: Any]]) ?? []
        let tasks = rawTasks.compactMap { dict -> ArgTask? in
            guard let id = dict["id"] as? String, !id.isEmpty else { return nil }
            let description = (dict["description"] as? String) ?? ""
            return ArgTask(id: id, description: description)
        }
        return (agent, tasks)
    }

    /// Fallback used when `argumentsJSON` is missing: extract the agent
    /// name out of the `"explore × 3"` summary string written by
    /// `SessionAgent.buildToolSummary`.
    private static func agentLabelFromSummary(_ summary: String) -> String {
        if let xIdx = summary.range(of: " × ") {
            return String(summary[..<xIdx.lowerBound])
        }
        return summary
    }
}

/// Collapsible row for a `task` tool call. The header shows `N
/// subagents · <agent>` plus an aggregate status icon; expanding it
/// reveals one row per parallel subagent. Each subagent row is itself
/// independently collapsible — the inner tool timeline and final
/// output only appear when the user opts in. This keeps the chat
/// scrollback compact when fanouts are common.
struct TaskFanoutRow: View {
    let model: TaskFanoutModel
    let isLast: Bool
    let isActive: Bool

    @State private var isExpanded = false
    @State private var pulseOn = false

    private var shouldPulse: Bool {
        model.overallStatus == .running && isActive
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Left rail: keeps visual continuity with regular tool rows.
            VStack(spacing: 0) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(iconColor)
                    .frame(width: 22, height: 22)
                if !isLast {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 22)

            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(headerText)
                            .chatFont(.body)
                            .foregroundColor(.primary.opacity(0.92))
                            .opacity(shouldPulse && pulseOn ? 0.45 : 1.0)

                        statusBadges

                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.6))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
                .buttonStyle(.plain)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.entries) { entry in
                            TaskSubagentRow(entry: entry)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            guard shouldPulse else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulseOn.toggle()
            }
        }
    }

    private var headerText: String {
        let total = model.entries.count
        switch model.overallStatus {
        case .running:
            return L10n.tr("tool.task.running_n", total, model.agentLabel)
        case .success, .failed:
            return L10n.tr("tool.task.ran_n", total, model.agentLabel)
        }
    }

    /// Per-status mini badges next to the title — "2 ✓, 1 ✗" — so the
    /// user can scan batch state without expanding.
    @ViewBuilder
    private var statusBadges: some View {
        let succeeded = model.entries.filter { $0.status == .success }.count
        let failed = model.entries.filter { $0.status == .failed }.count
        let running = model.entries.filter { $0.status == .running }.count

        HStack(spacing: 6) {
            if succeeded > 0 {
                Label("\(succeeded)", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .chatFont(.caption, weight: .medium)
                    .foregroundColor(.green)
            }
            if failed > 0 {
                Label("\(failed)", systemImage: "xmark.octagon.fill")
                    .labelStyle(.titleAndIcon)
                    .chatFont(.caption, weight: .medium)
                    .foregroundColor(.red)
            }
            if running > 0 {
                Label("\(running)", systemImage: "circle.dotted")
                    .labelStyle(.titleAndIcon)
                    .chatFont(.caption, weight: .medium)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var iconColor: Color {
        switch model.overallStatus {
        case .running: return .secondary
        case .success: return .secondary
        case .failed:  return .red
        }
    }
}

/// One subagent's row inside a `TaskFanoutRow`. Always shows id +
/// description + status; expanding it reveals the inner tool calls
/// the subagent made (live or persisted) plus the final output text.
struct TaskSubagentRow: View {
    let entry: TaskFanoutTaskEntry

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(statusColor)
                        .frame(width: 14)

                    Text(entry.id)
                        .chatFont(.footnote, weight: .semibold)
                        .foregroundColor(.primary.opacity(0.9))

                    if !entry.description.isEmpty {
                        Text(entry.description)
                            .chatFont(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 4)

                    if entry.steps > 0 {
                        Text("\(entry.steps) steps")
                            .chatFont(.caption, design: .monospaced)
                            .foregroundColor(.secondary.opacity(0.8))
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.5))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                expandedDetail
                    .padding(.leading, 22)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.04))
        )
    }

    @ViewBuilder
    private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !entry.innerTools.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.tr("tool.task.inner_tools"))
                        .chatFont(.caption, weight: .semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    ForEach(entry.innerTools) { inner in
                        TaskSubagentInnerToolRow(tool: inner)
                    }
                }
            }

            if let error = entry.error, !error.isEmpty {
                Text(error)
                    .chatFont(.caption)
                    .foregroundColor(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !entry.output.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.tr("tool.task.final_output"))
                        .chatFont(.caption, weight: .semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    ScrollView {
                        Text(entry.output)
                            .chatFont(.caption)
                            .foregroundColor(.primary.opacity(0.85))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                }
            }
        }
    }

    private var statusIcon: String {
        switch entry.status {
        case .running: return "circle.dotted"
        case .success: return "checkmark.circle.fill"
        case .failed:  return "xmark.octagon.fill"
        }
    }

    private var statusColor: Color {
        switch entry.status {
        case .running: return .secondary
        case .success: return .green
        case .failed:  return .red
        }
    }
}

/// Inline timeline row for one tool call inside a subagent. Compact —
/// the user is already two levels deep, so the row stays single-line
/// and the output is hidden behind another disclosure.
private struct TaskSubagentInnerToolRow: View {
    let tool: TaskFanoutInnerTool

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                withAnimation(.easeInOut(duration: 0.12)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(statusColor)
                        .frame(width: 12)
                    Text(tool.toolName)
                        .chatFont(.caption, weight: .medium)
                        .foregroundColor(.primary.opacity(0.85))
                    Text(tool.summary)
                        .chatFont(.caption, design: .monospaced)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    if !tool.output.isEmpty {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.5))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
            }
            .buttonStyle(.plain)

            if isExpanded, !tool.output.isEmpty {
                ScrollView {
                    Text(tool.output)
                        .chatFont(.caption, design: .monospaced)
                        .foregroundColor(.primary.opacity(0.8))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
            }
        }
    }

    private var statusIcon: String {
        switch tool.status {
        case .running: return "circle.dotted"
        case .success: return "checkmark.circle"
        case .failed:  return "xmark.octagon"
        }
    }

    private var statusColor: Color {
        switch tool.status {
        case .running: return .secondary
        case .success: return .green
        case .failed:  return .red
        }
    }
}
