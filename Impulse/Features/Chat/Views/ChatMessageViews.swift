import SwiftCodingAgent
import AppKit
import MarkdownUI
import SwiftUI

struct ChatWelcomeHeader: View {
    var body: some View {
        Text("Hi there! How can I help you today?")
            .font(.system(size: 28, weight: .semibold))
            .foregroundColor(.primary.opacity(0.88))
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
            .padding(.bottom, 14)
    }
}

struct TypingIndicatorView: View {
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
                Capsule().fill(Color.white.opacity(0.55))
            )
            Spacer()
        }
        .padding(.horizontal, 56)
        .onAppear { animating = true }
    }
}

struct MessageView: View {
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
                        .background(Color.white.opacity(0.55))
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
}

struct ToolExecutionMessageView: View {
    let execution: AgentToolExecution
    @State private var showFullOutput = false

    private var outputPreview: String {
        execution.output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first ?? ""
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(
                        systemName: execution.status == .success
                            ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .foregroundColor(execution.status == .success ? .green : .red)
                    .frame(width: 14)

                    HStack(spacing: 6) {
                        Image(systemName: toolIcon(for: execution.toolName))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(execution.toolName.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 70, alignment: .leading)

                    Text(execution.summary)
                        .font(
                            .system(
                                size: 11,
                                design: execution.toolName == "bash" ? .monospaced : .default)
                        )
                        .textSelection(.enabled)

                    Spacer()
                }

                if execution.toolName == "bash" {
                    DisclosureGroup(isExpanded: $showFullOutput) {
                        ScrollView {
                            Text(execution.output.isEmpty ? "(无输出)" : execution.output)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(maxHeight: 220)
                        .background(Color(NSColor.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8))
                                .rotationEffect(.degrees(showFullOutput ? 90 : 0))
                            Text("Full cmd result")
                        }
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .contentShape(Rectangle())
                    }
                } else {
                    Text(outputPreview)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
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

struct PersistedToolExecutionMessageView: View {
    let execution: PersistedToolExecution
    @State private var showFullOutput = false

    private var outputPreview: String {
        execution.output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first ?? ""
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(
                        systemName: execution.status == "success"
                            ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .foregroundColor(execution.status == "success" ? .green : .red)
                    .frame(width: 14)

                    HStack(spacing: 6) {
                        Image(systemName: toolIcon(for: execution.toolName))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(execution.toolName.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 70, alignment: .leading)

                    Text(execution.summary)
                        .font(
                            .system(
                                size: 11,
                                design: execution.toolName == "bash" ? .monospaced : .default)
                        )
                        .textSelection(.enabled)

                    Spacer()
                }

                if execution.toolName == "bash" {
                    DisclosureGroup(isExpanded: $showFullOutput) {
                        ScrollView {
                            Text(execution.output.isEmpty ? "(无输出)" : execution.output)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(maxHeight: 220)
                        .background(Color(NSColor.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8))
                                .rotationEffect(.degrees(showFullOutput ? 90 : 0))
                            Text("Full cmd result")
                        }
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .contentShape(Rectangle())
                    }
                } else {
                    Text(outputPreview)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
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
