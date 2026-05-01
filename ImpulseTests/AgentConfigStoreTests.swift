import XCTest
@testable import Impulse

final class AgentConfigStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AgentConfigStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Helpers

    private func encodeConfig(_ config: AgentServiceConfig) -> Data {
        try! JSONEncoder().encode(config)
    }

    // MARK: - Tests

    func test_load_emptyDefaults_returnsEnvironmentDefault() {
        let store = AgentConfigStore(defaults: defaults)
        let cfg = store.load()
        // The env-derived default uses ollama base URL when nothing is set.
        XCTAssertFalse(cfg.baseURL.isEmpty)
        XCTAssertFalse(cfg.providerId.isEmpty)
    }

    func test_save_thenLoad_roundTrips() {
        let store = AgentConfigStore(defaults: defaults)
        let original = AgentServiceConfig(
            providerId: "openai",
            baseURL: "https://api.openai.com/v1",
            apiKey: "sk-test",
            modelId: "gpt-4o"
        )
        store.save(original)

        let loaded = store.load()
        XCTAssertEqual(loaded, original)
    }

    /// V3 takes priority over V2 even if both keys exist.
    func test_load_prefersV3OverV2() {
        let v3 = AgentServiceConfig(providerId: "v3-provider", baseURL: "v3", apiKey: "v3-key", modelId: "v3-model")
        let v2 = AgentServiceConfig(providerId: "v2-provider", baseURL: "v2", apiKey: "v2-key", modelId: "v2-model")

        defaults.set(encodeConfig(v3), forKey: "agent.service.config.v3")
        defaults.set(encodeConfig(v2), forKey: "agent.service.config.v2")

        let loaded = AgentConfigStore(defaults: defaults).load()
        XCTAssertEqual(loaded, v3)
    }

    /// When V3 missing, fall back to V2.
    func test_load_fallsBackToV2_whenV3Missing() {
        let v2 = AgentServiceConfig(providerId: "v2-provider", baseURL: "v2", apiKey: "v2-key", modelId: "v2-model")
        defaults.set(encodeConfig(v2), forKey: "agent.service.config.v2")

        let loaded = AgentConfigStore(defaults: defaults).load()
        XCTAssertEqual(loaded, v2)
    }

    /// V1 takes lowest priority but still works for users upgrading from a
    /// very old build.
    func test_load_fallsBackToV1_whenNothingNewer() {
        let v1 = AgentServiceConfig(providerId: "v1-provider", baseURL: "v1", apiKey: "v1-key", modelId: "v1-model")
        defaults.set(encodeConfig(v1), forKey: "agent.service.config.v1")

        let loaded = AgentConfigStore(defaults: defaults).load()
        XCTAssertEqual(loaded, v1)
    }

    /// A corrupted V3 entry must not block a valid V2 fallback.
    func test_load_skipsCorruptedV3_andFallsBackToV2() {
        defaults.set(Data("not-json".utf8), forKey: "agent.service.config.v3")
        let v2 = AgentServiceConfig(providerId: "v2", baseURL: "v2", apiKey: "v2", modelId: "v2")
        defaults.set(encodeConfig(v2), forKey: "agent.service.config.v2")

        let loaded = AgentConfigStore(defaults: defaults).load()
        XCTAssertEqual(loaded, v2)
    }

    /// Saving always writes to V3, never to legacy keys.
    func test_save_writesToV3Only() {
        let store = AgentConfigStore(defaults: defaults)
        store.save(AgentServiceConfig(providerId: "p", baseURL: "b", apiKey: "k", modelId: "m"))

        XCTAssertNotNil(defaults.data(forKey: "agent.service.config.v3"))
        XCTAssertNil(defaults.data(forKey: "agent.service.config.v2"))
        XCTAssertNil(defaults.data(forKey: "agent.service.config.v1"))
    }
}
