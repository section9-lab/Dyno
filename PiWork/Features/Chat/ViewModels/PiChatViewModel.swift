import Foundation
import Combine

struct PiChatMessage: Identifiable, Equatable {
    enum Role: Equatable { case user, assistant, tool, system }

    let id: UUID
    let role: Role
    var text: String
    var isStreaming: Bool

    init(id: UUID = UUID(), role: Role, text: String, isStreaming: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.isStreaming = isStreaming
    }
}

/// Drives one `PiAgentProcess` for a single project and exposes a simple
/// transcript + running-state for `ChatView`. This is the seam where the
/// pi RPC protocol's streaming events get turned into something a SwiftUI
/// view can render directly.
@MainActor
final class PiChatViewModel: ObservableObject {
    @Published private(set) var messages: [PiChatMessage] = []
    @Published private(set) var isRunning = false
    @Published private(set) var isAgentBusy = false
    @Published private(set) var errorMessage: String?

    let project: PiProject
    private let agent: PiAgentProcess
    private var cancellables = Set<AnyCancellable>()
    private var currentAssistantMessageID: UUID?

    init(project: PiProject) {
        self.project = project
        self.agent = PiAgentProcess(projectPath: project.path)

        agent.$isRunning
            .receive(on: DispatchQueue.main)
            .assign(to: &$isRunning)

        agent.$lastError
            .receive(on: DispatchQueue.main)
            .assign(to: &$errorMessage)

        agent.messages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in self?.handle(message) }
            .store(in: &cancellables)
    }

    func ensureStarted() {
        guard !agent.isRunning else { return }
        do {
            try agent.start()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        ensureStarted()

        messages.append(PiChatMessage(role: .user, text: trimmed))
        isAgentBusy = true
        currentAssistantMessageID = nil

        do {
            try agent.sendPrompt(trimmed)
        } catch {
            errorMessage = error.localizedDescription
            isAgentBusy = false
        }
    }

    func stop() {
        agent.stop()
    }

    private func currentAssistantMessage() -> PiChatMessage? {
        guard let id = currentAssistantMessageID else { return nil }
        return messages.first { $0.id == id }
    }

    private func appendToAssistantMessage(_ delta: String) {
        if let id = currentAssistantMessageID,
           let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index].text += delta
        } else {
            let message = PiChatMessage(role: .assistant, text: delta, isStreaming: true)
            currentAssistantMessageID = message.id
            messages.append(message)
        }
    }

    private func finishAssistantMessage() {
        if let id = currentAssistantMessageID,
           let index = messages.firstIndex(where: { $0.id == id }) {
            messages[index].isStreaming = false
        }
        currentAssistantMessageID = nil
    }

    private func handle(_ message: PiAgentServerMessage) {
        switch message {
        case .event(let event):
            handle(event)
        case .response(let response):
            if response.success == false, let error = response.error {
                errorMessage = error
            }
        case .unknown:
            break
        }
    }

    private func handle(_ event: PiAgentEvent) {
        switch event {
        case .agentStart:
            isAgentBusy = true
        case .agentSettled:
            isAgentBusy = false
            finishAssistantMessage()
        case .textDelta(_, let delta):
            appendToAssistantMessage(delta)
        case .toolExecutionStart(_, let toolName, let argsSummary):
            let summary = argsSummary.map { " \($0)" } ?? ""
            messages.append(PiChatMessage(role: .tool, text: "▶ \(toolName)\(summary)"))
        case .toolExecutionEnd(_, let toolName, let isError):
            messages.append(PiChatMessage(role: .tool, text: isError ? "✗ \(toolName) failed" : "✓ \(toolName) done"))
        case .extensionError(let message):
            errorMessage = message
        default:
            break
        }
    }
}
