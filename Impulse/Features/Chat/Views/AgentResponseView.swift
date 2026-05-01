import SwiftCodingAgent
import SwiftUI

/// Isolated view that observes a SessionAgent for live tool executions and typing
/// indicator. Each session has its own SessionAgent so multiple sessions can
/// stream in parallel without overlapping into each other's UI.
struct AgentResponseView: View {
    @ObservedObject var sessionAgent: SessionAgent

    var body: some View {
        if sessionAgent.isResponding {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(sessionAgent.latestToolExecutions.enumerated()), id: \.element.id) { index, execution in
                    ToolExecutionMessageView(
                        execution: execution,
                        isLast: index == sessionAgent.latestToolExecutions.count - 1
                    )
                }
            }

            TypingIndicatorView()
        }
    }
}
