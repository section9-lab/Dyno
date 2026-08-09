import Foundation
import Combine

enum ProviderAuthFlowPhase: Equatable {
    case starting
    case waitingForProvider
    case waitingForUser
    case cancelling
    case succeeded
    case cancelled
    case failed

    var isTerminal: Bool {
        switch self {
        case .succeeded, .cancelled, .failed:
            return true
        case .starting, .waitingForProvider, .waitingForUser, .cancelling:
            return false
        }
    }
}

struct ProviderAuthDeviceCode: Equatable {
    let userCode: String
    let verificationURI: String
    let intervalSeconds: Int?
    let expiresInSeconds: Int?
}

struct ProviderAuthFlowState: Equatable, Identifiable {
    let id: String
    let providerId: String
    let providerName: String
    let method: AgentHostAuthMethod
    var phase: ProviderAuthFlowPhase
    var lastSequence: Int
    var prompt: AgentHostAuthPromptPayload?
    var authorizationURL: String?
    var authorizationInstructions: String?
    var deviceCode: ProviderAuthDeviceCode?
    var information: [String]
    var links: [AgentHostAuthInfoLink]
    var progressMessage: String?
    var errorMessage: String?
}

enum ProviderAuthEffect: Equatable {
    case reloadProviders
}

struct ProviderAuthReducer {
    private(set) var flow: ProviderAuthFlowState?

    mutating func begin(
        flowId: String,
        provider: AgentHostProvider,
        method: AgentHostAuthMethod
    ) {
        flow = ProviderAuthFlowState(
            id: flowId,
            providerId: provider.id,
            providerName: provider.name,
            method: method,
            phase: .starting,
            lastSequence: 0,
            prompt: nil,
            authorizationURL: nil,
            authorizationInstructions: nil,
            deviceCode: nil,
            information: [],
            links: [],
            progressMessage: nil,
            errorMessage: nil
        )
    }

    mutating func startAccepted(flowId: String) {
        guard var flow, flow.id == flowId, flow.phase == .starting else { return }
        flow.phase = .waitingForProvider
        self.flow = flow
    }

    mutating func responseAccepted(flowId: String, promptId: String) {
        guard var flow,
              flow.id == flowId,
              flow.prompt?.promptId == promptId else { return }
        flow.prompt = nil
        flow.phase = .waitingForProvider
        self.flow = flow
    }

    mutating func cancelRequested(flowId: String) {
        guard var flow, flow.id == flowId, !flow.phase.isTerminal else { return }
        flow.phase = .cancelling
        self.flow = flow
    }

    mutating func fail(flowId: String, message: String) {
        guard var flow, flow.id == flowId else { return }
        flow.phase = .failed
        flow.prompt = nil
        flow.errorMessage = message
        self.flow = flow
    }

    mutating func clear() {
        flow = nil
    }

    mutating func apply(_ event: AgentHostServerEvent) -> [ProviderAuthEffect] {
        if case .modelsChanged = event {
            return [.reloadProviders]
        }

        guard var flow else { return [] }
        switch event {
        case .authPrompt(let payload):
            guard accepts(
                flow: flow,
                flowId: payload.flowId,
                providerId: payload.providerId,
                sequence: payload.sequence
            ) else { return [] }
            flow.lastSequence = payload.sequence
            flow.prompt = payload
            flow.phase = .waitingForUser
        case .authPromptCancelled(let payload):
            guard accepts(
                flow: flow,
                flowId: payload.flowId,
                providerId: payload.providerId,
                sequence: payload.sequence
            ) else { return [] }
            flow.lastSequence = payload.sequence
            if flow.prompt?.promptId == payload.promptId {
                flow.prompt = nil
                flow.phase = .waitingForProvider
            }
        case .authNotice(let payload):
            guard accepts(
                flow: flow,
                flowId: payload.flowId,
                providerId: payload.providerId,
                sequence: payload.sequence
            ) else { return [] }
            flow.lastSequence = payload.sequence
            switch payload.notice {
            case .info(let message, let links):
                flow.information.append(message)
                for link in links where !flow.links.contains(where: { $0.url == link.url }) {
                    flow.links.append(link)
                }
            case .authURL(let url, let instructions):
                flow.authorizationURL = url
                flow.authorizationInstructions = instructions
            case .deviceCode(
                let userCode,
                let verificationURI,
                let intervalSeconds,
                let expiresInSeconds
            ):
                flow.deviceCode = ProviderAuthDeviceCode(
                    userCode: userCode,
                    verificationURI: verificationURI,
                    intervalSeconds: intervalSeconds,
                    expiresInSeconds: expiresInSeconds
                )
            case .progress(let message):
                flow.progressMessage = message
            }
            if flow.prompt == nil, flow.phase != .cancelling {
                flow.phase = .waitingForProvider
            }
        case .authFinished(let payload):
            guard accepts(
                flow: flow,
                flowId: payload.flowId,
                providerId: payload.providerId,
                sequence: payload.sequence
            ) else { return [] }
            flow.lastSequence = payload.sequence
            flow.prompt = nil
            switch payload.outcome {
            case .succeeded:
                flow.phase = .succeeded
            case .cancelled:
                flow.phase = .cancelled
            case .failed:
                flow.phase = .failed
                flow.errorMessage = payload.error?.message
            }
            self.flow = flow
            return [.reloadProviders]
        case .hostHello,
             .sessionStateChanged,
             .sessionMessageDelta,
             .sessionToolStarted,
             .sessionToolUpdated,
             .sessionToolCompleted,
             .sessionApprovalRequested,
             .sessionError,
             .modelsChanged,
             .unknown:
            return []
        }
        self.flow = flow
        return []
    }

    private func accepts(
        flow: ProviderAuthFlowState,
        flowId: String,
        providerId: String,
        sequence: Int
    ) -> Bool {
        flow.id == flowId
            && flow.providerId == providerId
            && sequence > flow.lastSequence
            && !flow.phase.isTerminal
    }
}

@MainActor
final class ProviderAuthStore: ObservableObject {
    @Published private(set) var providers: [AgentHostProvider] = []
    @Published private(set) var flow: ProviderAuthFlowState?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let service: any ProviderAuthServicing
    private var reducer = ProviderAuthReducer()
    private var eventTask: Task<Void, Never>?

    init(service: any ProviderAuthServicing) {
        self.service = service
    }

    func start() async {
        if eventTask == nil {
            let events = await service.events()
            eventTask = Task { [weak self] in
                for await event in events {
                    guard !Task.isCancelled else { return }
                    self?.receive(event)
                }
            }
        }
        await reloadProviders()
    }

    func stop() {
        eventTask?.cancel()
        eventTask = nil
    }

    func reloadProviders() async {
        isLoading = true
        defer { isLoading = false }
        do {
            providers = try await service.listProviders(requestID: UUID().uuidString)
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func beginAuthentication(
        provider: AgentHostProvider,
        method: AgentHostAuthMethod
    ) async {
        guard flow?.phase.isTerminal != false else { return }
        let flowId = UUID().uuidString
        reducer.begin(flowId: flowId, provider: provider, method: method)
        publishFlow()
        do {
            _ = try await service.startAuthentication(
                flowId: flowId,
                providerId: provider.id,
                method: method,
                requestID: UUID().uuidString
            )
            reducer.startAccepted(flowId: flowId)
            publishFlow()
        } catch {
            reducer.fail(flowId: flowId, message: String(describing: error))
            publishFlow()
        }
    }

    func respond(value: String) async {
        guard let flow, let prompt = flow.prompt else { return }
        do {
            _ = try await service.respondToAuthentication(
                flowId: flow.id,
                promptId: prompt.promptId,
                value: value,
                requestID: UUID().uuidString
            )
            reducer.responseAccepted(flowId: flow.id, promptId: prompt.promptId)
            publishFlow()
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func cancelAuthentication() async {
        guard let flow, !flow.phase.isTerminal else { return }
        reducer.cancelRequested(flowId: flow.id)
        publishFlow()
        do {
            _ = try await service.cancelAuthentication(
                flowId: flow.id,
                requestID: UUID().uuidString
            )
        } catch {
            reducer.fail(flowId: flow.id, message: String(describing: error))
            publishFlow()
        }
    }

    func logout(provider: AgentHostProvider) async {
        do {
            let result = try await service.logoutProvider(
                providerId: provider.id,
                requestID: UUID().uuidString
            )
            if let index = providers.firstIndex(where: { $0.id == result.provider.id }) {
                providers[index] = result.provider
            }
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func clearFlow() {
        guard flow?.phase.isTerminal != false else { return }
        reducer.clear()
        publishFlow()
    }

    private func receive(_ event: AgentHostServerEvent) {
        let effects = reducer.apply(event)
        publishFlow()
        for effect in effects {
            switch effect {
            case .reloadProviders:
                Task { await reloadProviders() }
            }
        }
    }

    private func publishFlow() {
        flow = reducer.flow
    }
}

@MainActor
final class AgentSettingsStore: ObservableObject {
    @Published private(set) var settings: AgentHostSettings?
    @Published private(set) var models: [AgentHostModel] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var errorMessage: String?

    private let service: any AgentSettingsServicing

    init(service: any AgentSettingsServicing) {
        self.service = service
    }

    func start() async {
        guard settings == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let loadedSettings = service.getAgentSettings(requestID: UUID().uuidString)
            async let loadedModels = service.listModels(requestID: UUID().uuidString)
            settings = try await loadedSettings
            models = try await loadedModels
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func update(_ patch: AgentHostSettingsPatch) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            settings = try await service.updateAgentSettings(
                patch,
                requestID: UUID().uuidString
            )
            errorMessage = nil
        } catch {
            errorMessage = String(describing: error)
        }
    }

    func reload() async {
        settings = nil
        await start()
    }
}
