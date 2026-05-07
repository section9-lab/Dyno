import Foundation
import SwiftHarnessAgent

@MainActor
final class ToolApprovalCenter: ObservableObject {
    static let shared = ToolApprovalCenter()

    @Published var pendingRequest: ToolApprovalRequest?

    private var continuations: [UUID: CheckedContinuation<ToolApprovalDecision, Never>] = [:]

    private init() {}

    func request(_ request: ToolApprovalRequest) async -> ToolApprovalDecision {
        await withCheckedContinuation { continuation in
            continuations[request.id] = continuation
            pendingRequest = request
        }
    }

    func approve(_ request: ToolApprovalRequest) {
        resolve(request, decision: .approved)
    }

    func reject(_ request: ToolApprovalRequest) {
        resolve(request, decision: .rejected)
    }

    private func resolve(_ request: ToolApprovalRequest, decision: ToolApprovalDecision) {
        pendingRequest = nil
        let continuation = continuations.removeValue(forKey: request.id)
        continuation?.resume(returning: decision)
    }
}
