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

    var body: some View {
        HStack {
            HStack(spacing: 10) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.gray.opacity(0.6))
                        .frame(width: 9, height: 9)
                        .scaleEffect(animating ? 1.0 : 0.5)
                        .opacity(animating ? 1.0 : 0.3)
                        .animation(
                            .easeInOut(duration: 0.5)
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

struct PersistedToolExecutionMessageView: View {
    let run: StoredToolRun
    var isLast: Bool = true

    var body: some View {
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

// MARK: - Group view (collapsible run of tool executions)

struct ToolExecutionGroup: Identifiable {
    let id: String
    let runs: [StoredToolRun]
}

/// Renders a contiguous run of persisted tool executions as a collapsible
/// timeline. Once finished, the user sees a one-line summary header that
/// can be re-expanded.
struct ToolExecutionGroupView: View {
    let group: ToolExecutionGroup

    @State private var isExpanded: Bool = true
    @State private var hasAutoCollapsed: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(group.runs.enumerated()), id: \.element.id) { index, run in
                        PersistedToolExecutionMessageView(
                            run: run,
                            // Last row keeps its connector so the rail flows
                            // into the Done marker that follows.
                            isLast: false
                        )
                    }

                    DoneTimelineMarker()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .onAppear {
            if !hasAutoCollapsed {
                isExpanded = false
                hasAutoCollapsed = true
            }
        }
    }

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Text(summaryText)
                    .chatFont(.body)
                    .foregroundColor(.secondary)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.6))
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))

                Spacer()
            }
            .padding(.horizontal, 56)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var summaryText: String {
        let count = group.runs.count
        let bashCount = group.runs.filter { $0.toolName == "bash" }.count
        let fileCount = group.runs.filter { ["read", "write", "edit"].contains($0.toolName) }.count

        if bashCount > 0 && fileCount > 0 {
            return "Ran \(bashCount) command\(bashCount == 1 ? "" : "s"), touched \(fileCount) file\(fileCount == 1 ? "" : "s")"
        }
        if bashCount > 0 {
            return "Ran \(bashCount) command\(bashCount == 1 ? "" : "s")"
        }
        if fileCount > 0 {
            return "Touched \(fileCount) file\(fileCount == 1 ? "" : "s")"
        }
        return "\(count) tool call\(count == 1 ? "" : "s")"
    }
}

/// Terminal cap for a tool-call timeline. Mirrors the original
/// `doneFooter` look (small SF Symbol + bold label, indented to line
/// up with the rail) but is a reusable component so it can be dropped
/// in wherever a group of timeline rows ends.
private struct DoneTimelineMarker: View {
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.primary.opacity(0.75))
                .frame(width: 22, height: 22)

            Text("chat.tool_group.done")
                .chatFont(.body, weight: .semibold)
                .foregroundColor(.primary.opacity(0.92))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 56)
        .padding(.top, 4)
    }
}

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
            return status == .running ? "Script" : "Script"
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
                if toolName == "task" {
                    taskOutputSection
                } else {
                    outputSection
                }
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

    /// Rendering for `task` tool output. The SDK joins per-task summaries
    /// as `## Task <id> (<agent>) — success/failed\nsteps: N\n...` blocks;
    /// we split and render them as individual cards so successes vs.
    /// failures are easy to scan.
    @ViewBuilder
    private var taskOutputSection: some View {
        let blocks = TaskOutputParser.parse(output)
        if blocks.isEmpty {
            outputSection
        } else {
            VStack(alignment: .leading, spacing: 8) {
                let succeeded = blocks.filter { $0.success }.count
                let failed = blocks.count - succeeded
                HStack(spacing: 8) {
                    if succeeded > 0 {
                        Label(L10n.tr("tool.task.success_count", succeeded), systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .chatFont(.footnote, weight: .medium)
                    }
                    if failed > 0 {
                        Label(L10n.tr("tool.task.failure_count", failed), systemImage: "xmark.octagon.fill")
                            .foregroundColor(.red)
                            .chatFont(.footnote, weight: .medium)
                    }
                    Spacer()
                }

                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    TaskOutputCard(block: block)
                }
            }
        }
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
