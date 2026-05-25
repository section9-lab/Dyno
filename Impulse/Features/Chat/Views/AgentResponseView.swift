import SwiftHarnessAgent
import MarkdownUI
import SwiftUI

/// Isolated view that observes a SessionAgent for the in-flight assistant
/// turn: the interleaved timeline of text blocks and tool calls (in the
/// exact emission order the model produced them), an optional collapsed
/// thinking pane, and a persistent typing indicator that stays at the
/// bottom until the run completes.
struct AgentResponseView: View {
    @ObservedObject var sessionAgent: SessionAgent

    /// The id of the tool execution currently in `.running`, if any.
    /// Used to drive the pulsing visual on the active row — earlier
    /// completed rows stay static, and the model rarely runs tools in
    /// true parallel so this is the one to draw attention to.
    private var lastRunningToolID: String? {
        for item in sessionAgent.liveTimeline.reversed() {
            if case .tool(let exec) = item, exec.status == .running {
                return exec.id
            }
        }
        return nil
    }

    var body: some View {
        if sessionAgent.isResponding || !sessionAgent.liveTimeline.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                if !sessionAgent.liveReasoningText.isEmpty {
                    LiveReasoningPane(text: sessionAgent.liveReasoningText)
                        .padding(.horizontal, 56)
                }

                ForEach(Array(sessionAgent.liveTimeline.enumerated()), id: \.element.id) { index, item in
                    switch item {
                    case .text(_, let content):
                        LiveAssistantBubble(text: content)
                            .padding(.horizontal, 56)
                    case .tool(let exec):
                        // Keep the connector running into the next row only
                        // when it's another tool — that gives back-to-back
                        // tools a single rail and cleanly breaks the rail
                        // when text or the typing dots interrupt the run.
                        let nextIsTool: Bool = {
                            let next = index + 1
                            guard next < sessionAgent.liveTimeline.count else { return false }
                            if case .tool = sessionAgent.liveTimeline[next] { return true }
                            return false
                        }()
                        ToolExecutionMessageView(
                            execution: exec,
                            isLast: !nextIsTool,
                            isActive: exec.id == lastRunningToolID
                        )
                    }
                }

                // Always-on typing dots: while the agent is responding, the
                // three pulsing dots sit at the bottom of the latest content
                // regardless of whether text, a tool, or a gap between tools
                // is the most recent event.
                if sessionAgent.isResponding {
                    TypingIndicatorView()
                        .padding(.horizontal, 56)
                }
            }
        }
    }
}

private struct LiveAssistantBubble: View {
    let text: String
    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        // Streaming uses MarkdownUI for rich formatting (code blocks, lists,
        // tables, links). To keep parsing/layout cost bounded, `SessionAgent`
        // throttles the timeline's text appends to ~10fps — so MarkdownUI
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
