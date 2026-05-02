import SwiftCodingAgent
import MarkdownUI
import SwiftUI

/// Isolated view that observes a SessionAgent for live tool executions, the
/// assistant's streaming partial answer, an optional collapsed thinking pane,
/// and a typing indicator. Each session has its own SessionAgent so multiple
/// sessions can stream in parallel without overlapping into each other's UI.
struct AgentResponseView: View {
    @ObservedObject var sessionAgent: SessionAgent

    /// True once at least one tool has run and *every* execution has left
    /// the `.running` state. Drives the live `Done` marker so the visual
    /// order mirrors the temporal one: tools → Done → assistant text.
    private var allToolsFinished: Bool {
        !sessionAgent.latestToolExecutions.isEmpty
            && sessionAgent.latestToolExecutions.allSatisfy { $0.status != .running }
    }

    /// Index of the last execution still in `.running`, or `nil` if none.
    /// Only that row pulses — earlier completed rows stay static, and the
    /// model rarely runs tools in true parallel so this is the right one
    /// to draw attention to.
    private var lastRunningIndex: Int? {
        sessionAgent.latestToolExecutions.lastIndex(where: { $0.status == .running })
    }

    var body: some View {
        if sessionAgent.isResponding {
            VStack(alignment: .leading, spacing: 12) {
                if !sessionAgent.liveReasoningText.isEmpty {
                    LiveReasoningPane(text: sessionAgent.liveReasoningText)
                        .padding(.horizontal, 56)
                }

                ForEach(Array(sessionAgent.latestToolExecutions.enumerated()), id: \.element.id) { index, execution in
                    ToolExecutionMessageView(
                        execution: execution,
                        isLast: index == sessionAgent.latestToolExecutions.count - 1,
                        isActive: index == lastRunningIndex
                    )
                }

                if allToolsFinished {
                    LiveDoneMarker()
                }

                if !sessionAgent.liveAssistantText.isEmpty {
                    LiveAssistantBubble(text: sessionAgent.liveAssistantText)
                        .padding(.horizontal, 56)
                } else if sessionAgent.latestToolExecutions.isEmpty {
                    // Pre-tool thinking — show the typing indicator. Once
                    // tools are running the executions themselves convey
                    // activity, and once they're done the Done marker does.
                    TypingIndicatorView()
                }
            }
        }
    }
}

private struct LiveDoneMarker: View {
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

private struct LiveAssistantBubble: View {
    let text: String
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        // Streaming uses MarkdownUI for rich formatting (code blocks, lists,
        // tables, links). To keep parsing/layout cost bounded, `SessionAgent`
        // throttles `liveAssistantText` updates to ~10fps — so MarkdownUI
        // only re-parses ~10 times per second instead of once per token.
        // That keeps the main thread responsive (scroll wheel, clicks) while
        // still feeling like real-time streaming.
        Markdown(text)
            .markdownTextStyle {
                FontSize(14 * themeManager.textSize.multiplier)
            }
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LiveReasoningPane: View {
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
    }
}
