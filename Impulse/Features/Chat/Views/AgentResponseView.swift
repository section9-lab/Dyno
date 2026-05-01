import SwiftCodingAgent
import MarkdownUI
import SwiftUI

/// Isolated view that observes a SessionAgent for live tool executions, the
/// assistant's streaming partial answer, an optional collapsed thinking pane,
/// and a typing indicator. Each session has its own SessionAgent so multiple
/// sessions can stream in parallel without overlapping into each other's UI.
struct AgentResponseView: View {
    @ObservedObject var sessionAgent: SessionAgent

    var body: some View {
        if sessionAgent.isResponding {
            VStack(alignment: .leading, spacing: 12) {
                // Reasoning streams in *before* tool calls (the model thinks,
                // then decides which tool to invoke). Show the live thinking
                // pane on top so the visual order matches the temporal order.
                // Default collapsed — expanding it during streaming makes the
                // pane balloon to fill the viewport, which traps the ScrollView
                // at the bottom and prevents the user from scrolling up.
                if !sessionAgent.liveReasoningText.isEmpty {
                    LiveReasoningPane(text: sessionAgent.liveReasoningText)
                        .padding(.horizontal, 56)
                }

                ForEach(Array(sessionAgent.latestToolExecutions.enumerated()), id: \.element.id) { index, execution in
                    ToolExecutionMessageView(
                        execution: execution,
                        isLast: index == sessionAgent.latestToolExecutions.count - 1
                    )
                }

                if !sessionAgent.liveAssistantText.isEmpty {
                    LiveAssistantBubble(text: sessionAgent.liveAssistantText)
                        .padding(.horizontal, 56)
                } else {
                    TypingIndicatorView()
                }
            }
        }
    }
}

private struct LiveAssistantBubble: View {
    let text: String

    var body: some View {
        // Streaming uses MarkdownUI for rich formatting (code blocks, lists,
        // tables, links). To keep parsing/layout cost bounded, `SessionAgent`
        // throttles `liveAssistantText` updates to ~10fps — so MarkdownUI
        // only re-parses ~10 times per second instead of once per token.
        // That keeps the main thread responsive (scroll wheel, clicks) while
        // still feeling like real-time streaming.
        Markdown(text)
            .markdownTextStyle {
                FontSize(14)
            }
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LiveReasoningPane: View {
    let text: String

    // Default collapsed during streaming. With the pane expanded, the live
    // text accumulates fast and pushes the pane height past the viewport,
    // which (combined with auto-scroll-to-bottom) traps the user's scroll
    // gesture. Collapsed is also consistent with PersistedReasoningRow
    // shown after the run finishes.
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
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.secondary)
                    Text("Thinking")
                        .font(.system(size: 12, weight: .medium))
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
                    .font(.system(size: 12))
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
