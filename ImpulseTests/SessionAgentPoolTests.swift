import XCTest
import SwiftCodingAgent
@testable import Impulse

@MainActor
final class SessionAgentPoolTests: XCTestCase {

    /// Build a real `AgentSDK` via the production factory. Pool tests don't
    /// call `.run()` on it — we only need an instance to populate
    /// `SessionAgent`. The factory is pure given inputs, so this is fast.
    private func makePool(softCap: Int = 8) -> SessionAgentPool {
        let pool = SessionAgentPool { projectPath in
            AgentSDKFactory.make(
                config: AgentServiceConfig(
                    providerId: "ollama",
                    baseURL: "http://127.0.0.1:11434/v1",
                    apiKey: "",
                    modelId: "llama3"
                ),
                activeProjectPath: projectPath,
                storageDirectoryURL: FileManager.default.temporaryDirectory,
                defaultExecutionWorkspaceURL: FileManager.default.temporaryDirectory,
                sandboxRoots: []
            )
        }
        pool.softCap = softCap
        return pool
    }

    // MARK: - Tests

    func test_sessionAgent_createsNewAgent_andCachesIt() {
        let pool = makePool()
        let a1 = pool.sessionAgent(for: "s1", projectPath: "/p")
        let a2 = pool.sessionAgent(for: "s1", projectPath: "/p")
        XCTAssertTrue(a1 === a2, "Same id must return the same SessionAgent instance")
    }

    func test_sessionAgent_differentIds_areDistinct() {
        let pool = makePool()
        let a = pool.sessionAgent(for: "s1", projectPath: "/p")
        let b = pool.sessionAgent(for: "s2", projectPath: "/p")
        XCTAssertFalse(a === b)
        XCTAssertEqual(pool.sessionAgents.count, 2)
    }

    func test_existingSessionAgent_doesNotCreate() {
        let pool = makePool()
        XCTAssertNil(pool.existingSessionAgent(for: "ghost"))
        XCTAssertEqual(pool.sessionAgents.count, 0)
    }

    func test_discard_removesAndCancels() {
        let pool = makePool()
        _ = pool.sessionAgent(for: "s1", projectPath: "/p")
        pool.discardSessionAgent(for: "s1")
        XCTAssertNil(pool.existingSessionAgent(for: "s1"))
    }

    func test_evictLRU_dropsLeastRecentlyUsed() {
        let pool = makePool(softCap: 3)
        _ = pool.sessionAgent(for: "s1", projectPath: "/p")
        _ = pool.sessionAgent(for: "s2", projectPath: "/p")
        _ = pool.sessionAgent(for: "s3", projectPath: "/p")
        // Touch s1 so it becomes most-recent; s2 is now LRU.
        _ = pool.sessionAgent(for: "s1", projectPath: "/p")
        // Add s4 — pushes pool to 4 over cap of 3, must evict s2.
        _ = pool.sessionAgent(for: "s4", projectPath: "/p")

        XCTAssertNil(pool.existingSessionAgent(for: "s2"))
        XCTAssertNotNil(pool.existingSessionAgent(for: "s1"))
        XCTAssertNotNil(pool.existingSessionAgent(for: "s3"))
        XCTAssertNotNil(pool.existingSessionAgent(for: "s4"))
    }

    /// The focused session must never be evicted, even if it would be the
    /// LRU pick by simple ordering.
    func test_evictLRU_neverEvictsFocused() {
        let pool = makePool(softCap: 2)
        _ = pool.sessionAgent(for: "s1", projectPath: "/p")
        _ = pool.sessionAgent(for: "s2", projectPath: "/p")
        pool.focusedSessionID = "s1"
        // Add s3 → pool is over cap; s1 is LRU but focused, so s2 should go.
        _ = pool.sessionAgent(for: "s3", projectPath: "/p")

        XCTAssertNotNil(pool.existingSessionAgent(for: "s1"),
                        "Focused session must survive eviction")
        XCTAssertNil(pool.existingSessionAgent(for: "s2"))
        XCTAssertNotNil(pool.existingSessionAgent(for: "s3"))
    }

    /// In-flight (responding) sessions are also protected from eviction —
    /// killing their SDK mid-run would lose the conversation.
    func test_evictLRU_neverEvictsResponding() {
        let pool = makePool(softCap: 2)
        let a1 = pool.sessionAgent(for: "s1", projectPath: "/p")
        _ = pool.sessionAgent(for: "s2", projectPath: "/p")
        a1.isResponding = true   // simulate in-flight chat
        // Add s3 → over cap; s1 is LRU but responding, so s2 should go.
        _ = pool.sessionAgent(for: "s3", projectPath: "/p")

        XCTAssertNotNil(pool.existingSessionAgent(for: "s1"),
                        "Responding session must not be evicted mid-run")
        XCTAssertNil(pool.existingSessionAgent(for: "s2"))
    }

    func test_isAnyResponding_reflectsAtLeastOneAgent() {
        let pool = makePool()
        let a = pool.sessionAgent(for: "s1", projectPath: "/p")
        XCTAssertFalse(pool.isAnyResponding)
        a.isResponding = true
        XCTAssertTrue(pool.isAnyResponding)
        a.isResponding = false
        XCTAssertFalse(pool.isAnyResponding)
    }

    func test_resetSessionAgent_replacesSDK_keepsSameInstance() {
        let pool = makePool()
        let a = pool.sessionAgent(for: "s1", projectPath: "/p")
        pool.resetSessionAgent(for: "s1", projectPath: "/p")
        let after = pool.existingSessionAgent(for: "s1")
        XCTAssertTrue(a === after, "resetSessionAgent should replace SDK in place, not the SessionAgent itself")
    }

    /// `applyPendingConfigRebuild` is a no-op when nothing is pending
    /// (must not crash, must not throw).
    func test_applyPendingConfigRebuild_noPending_isNoOp() {
        let pool = makePool()
        _ = pool.sessionAgent(for: "s1", projectPath: "/p")
        pool.applyPendingConfigRebuild(for: "s1") // nothing queued — OK
        pool.applyPendingConfigRebuild(for: "ghost") // unknown id — OK
    }
}
