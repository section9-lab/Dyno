import SwiftCodingAgent
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

                    Text(message.timestamp, format: .dateTime.hour().minute())
                        .chatFont(.footnote)
                        .foregroundColor(.secondary)
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

                Text(message.timestamp, format: .dateTime.hour().minute())
                    .chatFont(.footnote)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 56)
        }
    }

    private var userMessageBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.075) : Color.white.opacity(0.55)
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
                            isLast: index == group.runs.count - 1
                        )
                    }

                    doneFooter
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

    private var doneFooter: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.primary.opacity(0.75))
            }
            .frame(width: 22, height: 22)

            Text("chat.tool_group.done")
                .chatFont(.body, weight: .semibold)
                .foregroundColor(.primary.opacity(0.92))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 56)
        .padding(.top, 4)
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
            // Left rail: icon + connector line
            VStack(spacing: 0) {
                ZStack {
                    Image(systemName: iconName)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(iconColor)
                        .opacity(shouldPulse && !pulseOn ? 0.35 : 1.0)
                        .scaleEffect(shouldPulse && pulseOn ? 1.05 : 1.0)
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
                        Text(titleText)
                            .chatFont(.body)
                            .foregroundColor(.primary.opacity(status == .running ? 0.7 : 0.92))

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
        default: return "wrench.and.screwdriver"
        }
    }

    private var iconColor: Color {
        switch status {
        case .running: return .accentColor
        case .success: return .primary.opacity(0.75)
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
            return "Running command"
        default:
            return toolName.capitalized
        }
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
        case "read", "write", "edit":
            return nil
        default:
            return nil
        }
    }

    private var chipBackground: Color {
        switch status {
        case .running: return Color.red.opacity(0.12)
        case .success: return Color.secondary.opacity(0.12)
        case .failed: return Color.red.opacity(0.18)
        }
    }

    private var chipForeground: Color {
        switch status {
        case .running: return Color.red.opacity(0.85)
        case .success: return .secondary
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
