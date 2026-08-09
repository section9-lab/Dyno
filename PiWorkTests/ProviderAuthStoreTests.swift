import XCTest
@testable import PiWork

final class ProviderAuthStoreTests: XCTestCase {
    func testReducerKeepsAuthorizationURLWhilePresentingManualCodePrompt() {
        var reducer = ProviderAuthReducer()
        reducer.begin(
            flowId: "flow-one",
            provider: makeProvider(),
            method: .oauth
        )

        _ = reducer.apply(
            .authNotice(
                AgentHostAuthNoticePayload(
                    flowId: "flow-one",
                    providerId: "openai-codex",
                    sequence: 1,
                    notice: .authURL(
                        url: "https://example.com/oauth",
                        instructions: "Continue in your browser"
                    )
                )
            )
        )
        _ = reducer.apply(
            .authPrompt(
                AgentHostAuthPromptPayload(
                    flowId: "flow-one",
                    providerId: "openai-codex",
                    sequence: 2,
                    promptId: "prompt-one",
                    type: .manualCode,
                    message: "Paste the authorization code",
                    placeholder: "Code",
                    options: nil
                )
            )
        )

        XCTAssertEqual(reducer.flow?.authorizationURL, "https://example.com/oauth")
        XCTAssertEqual(reducer.flow?.authorizationInstructions, "Continue in your browser")
        XCTAssertEqual(reducer.flow?.prompt?.promptId, "prompt-one")
        XCTAssertEqual(reducer.flow?.prompt?.type, .manualCode)
        XCTAssertEqual(reducer.flow?.phase, .waitingForUser)
    }

    func testReducerCancelsOnlyTheMatchingPromptAndFinishesFlowSeparately() {
        var reducer = ProviderAuthReducer()
        reducer.begin(
            flowId: "flow-one",
            provider: makeProvider(),
            method: .oauth
        )
        _ = reducer.apply(
            .authPrompt(
                AgentHostAuthPromptPayload(
                    flowId: "flow-one",
                    providerId: "openai-codex",
                    sequence: 1,
                    promptId: "prompt-one",
                    type: .secret,
                    message: "API key",
                    placeholder: nil,
                    options: nil
                )
            )
        )

        _ = reducer.apply(
            .authPromptCancelled(
                AgentHostAuthPromptCancelledPayload(
                    flowId: "flow-one",
                    providerId: "openai-codex",
                    sequence: 2,
                    promptId: "different-prompt"
                )
            )
        )
        XCTAssertEqual(reducer.flow?.prompt?.promptId, "prompt-one")

        _ = reducer.apply(
            .authPromptCancelled(
                AgentHostAuthPromptCancelledPayload(
                    flowId: "flow-one",
                    providerId: "openai-codex",
                    sequence: 3,
                    promptId: "prompt-one"
                )
            )
        )
        XCTAssertNil(reducer.flow?.prompt)
        XCTAssertEqual(reducer.flow?.phase, .waitingForProvider)

        let effects = reducer.apply(
            .authFinished(
                AgentHostAuthFinishedPayload(
                    flowId: "flow-one",
                    providerId: "openai-codex",
                    sequence: 4,
                    outcome: .succeeded,
                    error: nil
                )
            )
        )
        XCTAssertEqual(reducer.flow?.phase, .succeeded)
        XCTAssertEqual(effects, [.reloadProviders])
    }

    @MainActor
    func testStoreLoadsProvidersAndStartsAuthentication() async {
        let host = FakeProviderAuthHost(providers: [makeProvider()])
        let store = ProviderAuthStore(service: host)

        await store.start()
        await store.beginAuthentication(provider: makeProvider(), method: .oauth)

        XCTAssertEqual(store.providers.map(\.id), ["openai-codex"])
        XCTAssertEqual(store.flow?.providerId, "openai-codex")
        XCTAssertEqual(store.flow?.phase, .waitingForProvider)
        let starts = await host.starts
        XCTAssertEqual(starts.count, 1)
        XCTAssertEqual(starts.first?.providerId, "openai-codex")
        XCTAssertEqual(starts.first?.method, .oauth)
        store.stop()
    }

    private func makeProvider() -> AgentHostProvider {
        AgentHostProvider(
            id: "openai-codex",
            name: "OpenAI Codex",
            methods: [
                AgentHostProviderAuthMethod(
                    type: .oauth,
                    name: "OpenAI Codex OAuth",
                    loginLabel: "Sign in with ChatGPT"
                )
            ],
            status: AgentHostProviderAuthStatus(
                configured: false,
                source: nil,
                credentialType: nil,
                canDisconnect: false,
                label: nil
            ),
            models: AgentHostProviderModelCounts(total: 4, available: 0)
        )
    }
}

final class AgentSettingsStoreTests: XCTestCase {
    @MainActor
    func testStoreLoadsModelsAndPersistsASettingsPatch() async {
        let initial = AgentHostSettings(
            defaultModel: AgentHostDefaultModel(provider: "openai", modelId: "gpt-test"),
            defaultThinkingLevel: .high,
            transport: .auto,
            compactionEnabled: true,
            retryEnabled: true
        )
        let model = AgentHostModel(
            provider: "openai",
            id: "gpt-test",
            name: "GPT Test",
            contextWindow: 128_000,
            maxTokens: 16_384,
            reasoning: true,
            supportsImages: true
        )
        let host = FakeAgentSettingsHost(settings: initial, models: [model])
        let store = AgentSettingsStore(service: host)

        await store.start()
        await store.update(
            AgentHostSettingsPatch(
                defaultThinkingLevel: .max,
                compactionEnabled: false
            )
        )

        XCTAssertEqual(store.models, [model])
        XCTAssertEqual(store.settings?.defaultThinkingLevel, .max)
        XCTAssertEqual(store.settings?.compactionEnabled, false)
        XCTAssertFalse(store.isLoading)
        XCTAssertFalse(store.isSaving)
        XCTAssertNil(store.errorMessage)
        let patches = await host.patches
        XCTAssertEqual(patches.count, 1)
        XCTAssertEqual(patches[0].defaultThinkingLevel, .max)
        XCTAssertEqual(patches[0].compactionEnabled, false)
    }
}

private actor FakeProviderAuthHost: ProviderAuthServicing {
    struct Start: Equatable {
        let flowId: String
        let providerId: String
        let method: AgentHostAuthMethod
    }

    private let providersValue: [AgentHostProvider]
    private let stream: AsyncStream<AgentHostServerEvent>
    private let continuation: AsyncStream<AgentHostServerEvent>.Continuation
    private(set) var starts: [Start] = []

    init(providers: [AgentHostProvider]) {
        providersValue = providers
        var storedContinuation: AsyncStream<AgentHostServerEvent>.Continuation!
        stream = AsyncStream { storedContinuation = $0 }
        continuation = storedContinuation
    }

    func events() -> AsyncStream<AgentHostServerEvent> { stream }

    func listProviders(requestID: String) async throws -> [AgentHostProvider] {
        providersValue
    }

    func startAuthentication(
        flowId: String,
        providerId: String,
        method: AgentHostAuthMethod,
        requestID: String
    ) async throws -> AgentHostAuthStartResult {
        starts.append(Start(flowId: flowId, providerId: providerId, method: method))
        return AgentHostAuthStartResult(accepted: true, flowId: flowId)
    }

    func respondToAuthentication(
        flowId: String,
        promptId: String,
        value: String,
        requestID: String
    ) async throws -> AgentHostAuthAcceptedResult {
        AgentHostAuthAcceptedResult(accepted: true)
    }

    func cancelAuthentication(
        flowId: String,
        requestID: String
    ) async throws -> AgentHostAuthCancelResult {
        AgentHostAuthCancelResult(cancelRequested: true)
    }

    func logoutProvider(
        providerId: String,
        requestID: String
    ) async throws -> AgentHostAuthLogoutResult {
        AgentHostAuthLogoutResult(removed: false, provider: providersValue[0])
    }
}

private actor FakeAgentSettingsHost: AgentSettingsServicing {
    private var settingsValue: AgentHostSettings
    private let modelsValue: [AgentHostModel]
    private(set) var patches: [AgentHostSettingsPatch] = []

    init(settings: AgentHostSettings, models: [AgentHostModel]) {
        settingsValue = settings
        modelsValue = models
    }

    func listModels(requestID: String) async throws -> [AgentHostModel] {
        modelsValue
    }

    func getAgentSettings(requestID: String) async throws -> AgentHostSettings {
        settingsValue
    }

    func updateAgentSettings(
        _ patch: AgentHostSettingsPatch,
        requestID: String
    ) async throws -> AgentHostSettings {
        patches.append(patch)
        settingsValue = AgentHostSettings(
            defaultModel: patch.defaultModel ?? settingsValue.defaultModel,
            defaultThinkingLevel: patch.defaultThinkingLevel ?? settingsValue.defaultThinkingLevel,
            transport: patch.transport ?? settingsValue.transport,
            compactionEnabled: patch.compactionEnabled ?? settingsValue.compactionEnabled,
            retryEnabled: patch.retryEnabled ?? settingsValue.retryEnabled
        )
        return settingsValue
    }
}
