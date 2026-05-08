import Foundation
import SwiftHarnessAgent

/// One pending `ask` invocation. Holds the questions surfaced by the agent
/// plus the continuation that the SDK is awaiting. The UI layer (the
/// `AskPromptBanner`) reads `questions` for rendering and calls
/// `submit(...)` / `cancel()` to resume the agent loop.
struct AskPrompt: Identifiable {
    let id: UUID
    let questions: [AskQuestion]
}

/// `@MainActor` singleton that bridges the SDK's `AskHandler` (a sendable
/// async closure) to the SwiftUI surface.
///
/// Mirrors `ToolApprovalCenter`'s pattern: when the agent calls the `ask`
/// tool, the handler closure registers a continuation and publishes the
/// prompt. The chat surface displays it inline, the user submits answers,
/// and the continuation resumes — feeding the answers back into the model.
///
/// Only one prompt can be live at a time; chained asks will queue
/// implicitly because each agent run waits on the prior continuation
/// before issuing the next tool call.
@MainActor
final class AskCenter: ObservableObject {
    static let shared = AskCenter()

    @Published var pendingPrompt: AskPrompt?

    private var continuations: [UUID: CheckedContinuation<[AskAnswer], Error>] = [:]

    private init() {}

    /// Returns an `AskHandler` closure that bridges into this center. The
    /// closure is `@Sendable` because the SDK runs the agent loop off the
    /// main actor; `present(...)` hops back to the main actor before
    /// publishing.
    func makeHandler() -> AskHandler {
        return { [weak self] questions in
            guard let self else { throw AskError.noHandler }
            return try await self.present(questions: questions)
        }
    }

    /// User submitted answers for the current prompt. `answers.count` must
    /// match the prompt's question count; the order is the same as
    /// `pendingPrompt.questions`.
    func submit(_ answers: [AskAnswer]) {
        guard let prompt = pendingPrompt else { return }
        let continuation = continuations.removeValue(forKey: prompt.id)
        pendingPrompt = nil
        continuation?.resume(returning: answers)
    }

    /// User cancelled / dismissed the prompt. Surfaces `AskError.aborted`
    /// to the agent loop, which the SDK turns into a tool error.
    func cancel() {
        guard let prompt = pendingPrompt else { return }
        let continuation = continuations.removeValue(forKey: prompt.id)
        pendingPrompt = nil
        continuation?.resume(throwing: AskError.aborted)
    }

    private func present(questions: [AskQuestion]) async throws -> [AskAnswer] {
        let id = UUID()
        let prompt = AskPrompt(id: id, questions: questions)

        return try await withCheckedThrowingContinuation { continuation in
            // Store + publish on the main actor (we're already there because
            // the class is @MainActor-isolated).
            continuations[id] = continuation
            pendingPrompt = prompt
        }
    }
}
