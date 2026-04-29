import SwiftCodingAgent
import AppKit
import MarkdownUI
import SwiftUI

struct ChatWelcomeHeader: View {
    var body: some View {
        Text("chat.welcome")
            .font(.system(size: 28, weight: .semibold))
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

    let item: Item

    var body: some View {
        if item.isUser {
            HStack {
                Spacer(minLength: 80)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(item.content)
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 28)
                        .padding(.vertical, 16)
                        .background(userMessageBackground)
                        .foregroundColor(.primary)
                        .clipShape(Capsule())

                    Text(item.timestamp, format: .dateTime.hour().minute())
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 56)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Markdown(item.content)
                    .markdownTextStyle {
                        FontSize(14)
                    }
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                Text(item.timestamp, format: .dateTime.hour().minute())
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
        }
    }

    private var userMessageBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.075) : Color.white.opacity(0.55)
    }
}

struct ToolExecutionMessageView: View {
    let execution: AgentToolExecution

    var body: some View {
        ToolExecutionCard(
            toolName: execution.toolName,
            statusSucceeded: execution.status == .success,
            summary: execution.summary,
            output: execution.output
        )
    }
}

struct PersistedToolExecutionMessageView: View {
    let execution: PersistedToolExecution

    var body: some View {
        ToolExecutionCard(
            toolName: execution.toolName,
            statusSucceeded: execution.status == "success",
            summary: execution.summary,
            output: execution.output
        )
    }
}

private struct ToolExecutionCard: View {
    let toolName: String
    let statusSucceeded: Bool
    let summary: String
    let output: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: statusSucceeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(statusSucceeded ? .green : .red)
                        .frame(width: 14)

                    HStack(spacing: 6) {
                        Image(systemName: toolIcon(for: toolName))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(toolName.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 70, alignment: .leading)

                    Text(summary)
                        .font(.system(size: 11, design: toolName == "bash" ? .monospaced : .default))
                        .textSelection(.enabled)

                    Spacer()
                }

                ToolOutputPreview(toolName: toolName, output: output)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Spacer(minLength: 60)
        }
        .padding(.horizontal, 16)
    }

    private func toolIcon(for name: String) -> String {
        switch name {
        case "read": return "doc.text"
        case "write": return "square.and.pencil"
        case "edit": return "pencil.and.scribble"
        case "bash": return "terminal"
        default: return "wrench.and.screwdriver"
        }
    }
}

private struct ToolOutputPreview: View {
    private let collapsedLineLimit = 3
    private let expandedLineLimit = 10

    let toolName: String
    let output: String

    @State private var isExpanded = false

    private var displayOutput: String {
        let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedOutput.isEmpty ? L10n.tr("tool.no_output") : trimmedOutput
    }

    private var hasExpandableOutput: Bool {
        displayOutput.components(separatedBy: .newlines).count > collapsedLineLimit
    }

    private var fontDesign: Font.Design {
        switch toolName {
        case "bash", "edit": return .monospaced
        default: return .default
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(displayOutput)
                .font(.system(size: 10, design: fontDesign))
                .foregroundColor(.secondary)
                .textSelection(.enabled)
                .lineLimit(isExpanded ? expandedLineLimit : collapsedLineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)

            if hasExpandableOutput {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        Text(isExpanded ? L10n.tr("tool.show_less") : L10n.tr("tool.show_more"))
                    }
                    .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
        }
    }
}
