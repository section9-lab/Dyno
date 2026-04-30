import SwiftCodingAgent
import SwiftUI

/// Isolated view that observes AgentManager for live tool executions and typing indicator.
/// Prevents polling updates from triggering re-layout of the entire message list.
struct AgentResponseView: View {
    @ObservedObject var agent: AgentManager

    var body: some View {
        if agent.isResponding {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(agent.latestToolExecutions.enumerated()), id: \.element.id) { index, execution in
                    ToolExecutionMessageView(
                        execution: execution,
                        isLast: index == agent.latestToolExecutions.count - 1
                    )
                }
            }

            TypingIndicatorView()
        }
    }
}
