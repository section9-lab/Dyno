import SwiftAgent
import SwiftUI

/// Isolated view that observes AgentManager for live tool executions and typing indicator.
/// Prevents polling updates from triggering re-layout of the entire message list.
struct AgentResponseView: View {
    @ObservedObject var agent: AgentManager

    var body: some View {
        if agent.isResponding {
            ForEach(agent.latestToolExecutions) { execution in
                ToolExecutionMessageView(execution: execution)
            }

            TypingIndicatorView()
        }
    }
}
