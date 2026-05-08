import Foundation
import SwiftHarnessAgent

/// Owns the in-memory pool of `SessionAgent` instances + LRU eviction +
/// pending-config-rebuild book-keeping. Does not know how to *build* a
/// `SessionAgent` or rebuild its SDK — that's `AgentManager`'s job; the pool
/// just calls the supplied closures.
///
/// Threading: must be touched on the main actor (the agents themselves are
/// `@MainActor`), so the pool is too.
@MainActor
final class SessionAgentPool: ObservableObject {
    @Published private(set) var sessionAgents: [String: SessionAgent] = [:]

    /// Currently-focused session id (the one displayed in the chat view).
    /// Other sessions in `sessionAgents` may still be responding in the background.
    @Published var focusedSessionID: String?

    /// Soft cap on the number of cached SessionAgents.
    var softCap: Int = 8

    /// LRU access order — most recent at the end.
    private var lru: [String] = []

    /// Sessions whose SDK should be rebuilt the moment they finish their
    /// current run (config changed mid-flight).
    private var pendingConfigRebuild: Set<String> = []

    /// Creates a fresh `SessionAgent` for `(sessionID, projectPath)`. The
    /// owner (`AgentManager`) is responsible for wiring per-session
    /// productivity dependencies (TodoStore, ask handler, task coordinator)
    /// inside this closure.
    private let createSessionAgent: (_ sessionID: String, _ projectPath: String) -> SessionAgent

    /// Rebuilds an SDK for an *existing* SessionAgent, preserving its
    /// per-session productivity state (the same `TodoStore` keeps its tasks
    /// across config refreshes).
    private let rebuildSDK: (_ sessionAgent: SessionAgent) -> AgentSDK

    init(
        createSessionAgent: @escaping (_ sessionID: String, _ projectPath: String) -> SessionAgent,
        rebuildSDK: @escaping (_ sessionAgent: SessionAgent) -> AgentSDK
    ) {
        self.createSessionAgent = createSessionAgent
        self.rebuildSDK = rebuildSDK
    }

    // MARK: - Lookup / lifecycle

    @discardableResult
    func sessionAgent(for sessionID: String, projectPath: String) -> SessionAgent {
        touchLRU(sessionID)
        if let existing = sessionAgents[sessionID] {
            return existing
        }
        let agent = createSessionAgent(sessionID, projectPath)
        sessionAgents[sessionID] = agent
        evictLRUIfNeeded()
        return agent
    }

    func existingSessionAgent(for sessionID: String?) -> SessionAgent? {
        guard let sessionID else { return nil }
        return sessionAgents[sessionID]
    }

    /// Drops the SessionAgent for a deleted session, cancelling any in-flight task.
    func discardSessionAgent(for sessionID: String) {
        if let agent = sessionAgents.removeValue(forKey: sessionID) {
            agent.cancel()
        }
        lru.removeAll { $0 == sessionID }
        pendingConfigRebuild.remove(sessionID)
    }

    /// Reset a single session's SDK (start a fresh chat under the same id).
    /// Replaces the existing SessionAgent wholesale — the productivity
    /// state (todo list, etc.) does NOT carry over because the user is
    /// explicitly starting fresh.
    func resetSessionAgent(for sessionID: String, projectPath: String) {
        if let existing = sessionAgents[sessionID] {
            existing.cancel()
        }
        sessionAgents[sessionID] = createSessionAgent(sessionID, projectPath)
        touchLRU(sessionID)
        evictLRUIfNeeded()
    }

    var isAnyResponding: Bool {
        sessionAgents.values.contains(where: \.isResponding)
    }

    // MARK: - Config refresh

    /// Rebuild every *idle* SessionAgent's SDK. In-flight sessions are queued
    /// — they pick up the new config the moment they next become idle.
    /// Per-session state (todo list, ask center, task coordinator) is
    /// preserved because the SessionAgent instance itself stays alive.
    func refreshAllSDKs() {
        for (_, agent) in sessionAgents {
            if agent.isResponding {
                pendingConfigRebuild.insert(agent.id)
            } else {
                agent.replaceSDK(rebuildSDK(agent))
                pendingConfigRebuild.remove(agent.id)
            }
        }
    }

    /// Called by `SessionAgent` when it transitions back to idle.
    func applyPendingConfigRebuild(for sessionID: String) {
        guard pendingConfigRebuild.remove(sessionID) != nil,
              let agent = sessionAgents[sessionID]
        else { return }
        agent.replaceSDK(rebuildSDK(agent))
    }

    // MARK: - LRU

    private func touchLRU(_ sessionID: String) {
        lru.removeAll { $0 == sessionID }
        lru.append(sessionID)
    }

    private func evictLRUIfNeeded() {
        guard sessionAgents.count > softCap else { return }
        let evictable = lru.filter { id in
            id != focusedSessionID
                && (sessionAgents[id]?.isResponding == false)
        }
        let overflow = sessionAgents.count - softCap
        for id in evictable.prefix(overflow) {
            sessionAgents.removeValue(forKey: id)
            lru.removeAll { $0 == id }
        }
    }
}
