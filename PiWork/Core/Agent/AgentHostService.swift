import Foundation

enum AgentHostServiceError: Error {
    case executableNotFound
    case missingCapabilities([String])
    case stopped
}

enum AgentHostServiceLifecycleError: Error, Equatable {
    case connectionLost
}

enum AgentHostServiceLifecycleEvent: Equatable {
    case connected(generation: Int, hello: AgentHostHelloPayload)
    case disconnected(generation: Int, error: AgentHostServiceLifecycleError)
    case restarted(generation: Int, hello: AgentHostHelloPayload)
}

private struct StartedAgentHost {
    let client: AgentHostClient
    let hello: AgentHostHelloPayload
}

protocol AgentHostServicing: Actor {
    func events() -> AsyncStream<AgentHostServerEvent>
    func lifecycleEvents() -> AsyncStream<AgentHostServiceLifecycleEvent>
    func start() async throws -> AgentHostHelloPayload
    func stop() async
    func listSessions(
        cwd: String,
        sessionDirectory: String?,
        requestID: String
    ) async throws -> [AgentHostSessionSummary]
    func listModels(requestID: String) async throws -> [AgentHostModel]
    func gitBranches(
        cwd: String,
        requestID: String
    ) async throws -> AgentHostGitBranchesResult
    func createDraft(
        cwd: String,
        sessionDirectory: String?,
        profile: AgentHostSessionProfile,
        requestID: String
    ) async throws -> AgentHostSessionSummary
    func openSession(
        path: String,
        sessionDirectory: String?,
        profile: AgentHostSessionProfile,
        requestID: String
    ) async throws -> AgentHostSessionOpenResult
    func snapshot(
        sessionId: String,
        requestID: String
    ) async throws -> AgentHostSessionSnapshotResult
    func toolOutput(
        sessionId: String,
        toolCallId: String,
        requestID: String
    ) async throws -> AgentHostSessionToolOutputResult
    func listSlashCommands(
        sessionId: String,
        requestID: String
    ) async throws -> [AgentHostSlashCommand]
    func renameSession(
        sessionId: String,
        title: String,
        requestID: String
    ) async throws -> AgentHostSessionRenameResult
    func setGitBranch(
        sessionId: String,
        branch: String,
        requestID: String
    ) async throws -> AgentHostSessionSetGitBranchResult
    func setModel(
        sessionId: String,
        provider: String,
        modelId: String,
        requestID: String
    ) async throws -> AgentHostSessionSetModelResult
    func setModelOption(
        sessionId: String,
        option: AgentHostModelOption,
        enabled: Bool,
        requestID: String
    ) async throws -> AgentHostSessionSetModelOptionResult
    func setThinkingLevel(
        sessionId: String,
        thinkingLevel: AgentHostThinkingLevel,
        requestID: String
    ) async throws -> AgentHostSessionSetThinkingLevelResult
    func setAccessMode(
        sessionId: String,
        accessMode: AgentHostAccessMode,
        requestID: String
    ) async throws -> AgentHostSessionSetAccessModeResult
    func resolveApproval(
        sessionId: String,
        requestId: String,
        decision: AgentHostApprovalDecision,
        requestID: String
    ) async throws -> AgentHostSessionResolveApprovalResult
    func prompt(
        sessionId: String,
        turnId: String,
        text: String,
        images: [AgentHostPromptImage],
        requestID: String
    ) async throws -> AgentHostSessionPromptResult
    func abort(
        sessionId: String,
        requestID: String
    ) async throws -> AgentHostSessionAbortResult
    func closeSession(
        sessionId: String,
        requestID: String
    ) async throws -> AgentHostSessionCloseResult
    func deleteSession(
        sessionId: String,
        cwd: String,
        sessionDirectory: String?,
        requestID: String
    ) async throws -> AgentHostSessionDeleteResult
}

protocol ProviderAuthServicing: Actor {
    func events() -> AsyncStream<AgentHostServerEvent>
    func lifecycleEvents() -> AsyncStream<AgentHostServiceLifecycleEvent>
    func listProviders(requestID: String) async throws -> [AgentHostProvider]
    func startAuthentication(
        flowId: String,
        providerId: String,
        method: AgentHostAuthMethod,
        requestID: String
    ) async throws -> AgentHostAuthStartResult
    func respondToAuthentication(
        flowId: String,
        promptId: String,
        value: String,
        requestID: String
    ) async throws -> AgentHostAuthAcceptedResult
    func cancelAuthentication(
        flowId: String,
        requestID: String
    ) async throws -> AgentHostAuthCancelResult
    func logoutProvider(
        providerId: String,
        requestID: String
    ) async throws -> AgentHostAuthLogoutResult
}

protocol AgentSettingsServicing: Actor {
    func listModels(requestID: String) async throws -> [AgentHostModel]
    func getAgentSettings(requestID: String) async throws -> AgentHostSettings
    func updateAgentSettings(
        _ patch: AgentHostSettingsPatch,
        requestID: String
    ) async throws -> AgentHostSettings
}

protocol InstalledExtensionsServicing: Actor {
    func getPiWebAccessConfiguration(
        requestID: String
    ) async throws -> AgentHostPiWebAccessConfiguration
    func updatePiWebAccessConfiguration(
        _ configuration: AgentHostPiWebAccessConfiguration,
        requestID: String
    ) async throws -> AgentHostPiWebAccessConfiguration
    func listInstalledExtensions(
        requestID: String
    ) async throws -> [AgentHostInstalledExtensionPackage]
    func installExtension(
        source: String,
        requestID: String
    ) async throws -> [AgentHostInstalledExtensionPackage]
    func setInstalledExtensionEnabled(
        source: String,
        scope: AgentHostExtensionPackageScope,
        enabled: Bool,
        requestID: String
    ) async throws -> [AgentHostInstalledExtensionPackage]
    func updateInstalledExtension(
        source: String,
        scope: AgentHostExtensionPackageScope,
        requestID: String
    ) async throws -> [AgentHostInstalledExtensionPackage]
    func removeInstalledExtension(
        source: String,
        scope: AgentHostExtensionPackageScope,
        requestID: String
    ) async throws -> [AgentHostInstalledExtensionPackage]
}

actor AgentHostService: AgentHostServicing,
    ProviderAuthServicing,
    AgentSettingsServicing,
    InstalledExtensionsServicing {
    static let coreCapabilities: Set<String> = [
        "sessions.list",
        "models.list",
        "providers.list",
        "auth.start",
        "auth.respond",
        "auth.cancel",
        "auth.logout",
        "settings.get",
        "settings.update",
        "extensions.listInstalled",
        "extensions.install",
        "extensions.setEnabled",
        "extensions.update",
        "extensions.remove",
        "git.branches",
        "session.createDraft",
        "session.open",
        "session.snapshot",
        "session.toolOutput",
        "session.commands",
        "session.rename",
        "session.setGitBranch",
        "session.setAccessMode",
        "session.resolveApproval",
        "session.setModel",
        "session.setModelOption",
        "session.setThinkingLevel",
        "session.prompt",
        "session.promptImages",
        "session.abort",
        "session.close",
        "session.delete"
    ]

    static func bundled() throws -> AgentHostService {
        guard
            let executableURL = AgentHostExecutable.bundledURL(),
            let bunExecutableURL = AgentHostExecutable.bundledBunURL()
        else {
            throw AgentHostServiceError.executableNotFound
        }
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        let authenticationFile = AgentHostExecutable.authenticationFileURL(
            applicationSupportDirectory: applicationSupport
        )
        let agentDirectory = AgentHostExecutable.agentDirectoryURL(
            applicationSupportDirectory: applicationSupport
        )
        return AgentHostService(
            executableURL: executableURL,
            environment: [
                "PI_WORK_AUTH_PATH": authenticationFile.path,
                "PI_WORK_AGENT_DIR": agentDirectory.path,
                "PI_CODING_AGENT_DIR": agentDirectory.path,
                "PI_WORK_BUN_PATH": bunExecutableURL.path
            ],
            handshakeTimeout: 15
        )
    }

    private let executableURL: URL
    private let arguments: [String]
    private let environment: [String: String]
    private let requiredCapabilities: Set<String>
    private let handshakeTimeout: TimeInterval

    private var client: AgentHostClient?
    private var hello: AgentHostHelloPayload?
    private var eventContinuations: [
        UUID: AsyncStream<AgentHostServerEvent>.Continuation
    ] = [:]
    private var lifecycleContinuations: [
        UUID: AsyncStream<AgentHostServiceLifecycleEvent>.Continuation
    ] = [:]
    private var eventForwardingTask: Task<Void, Never>?
    private var clientGeneration = 0
    private var automaticRecoveryAttempted = false
    private var isStopping = false
    private var startupTask: Task<StartedAgentHost, Error>?

    init(
        executableURL: URL,
        arguments: [String] = [],
        environment: [String: String] = [:],
        requiredCapabilities: Set<String> = AgentHostService.coreCapabilities,
        handshakeTimeout: TimeInterval = 5
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.requiredCapabilities = requiredCapabilities
        self.handshakeTimeout = handshakeTimeout
    }

    func events() -> AsyncStream<AgentHostServerEvent> {
        let id = UUID()
        var continuation: AsyncStream<AgentHostServerEvent>.Continuation?
        let stream = AsyncStream<AgentHostServerEvent> { streamContinuation in
            continuation = streamContinuation
            streamContinuation.onTermination = { [weak self] _ in
                Task { await self?.removeEventSubscriber(id) }
            }
        }
        eventContinuations[id] = continuation
        return stream
    }

    func lifecycleEvents() -> AsyncStream<AgentHostServiceLifecycleEvent> {
        let id = UUID()
        var continuation: AsyncStream<AgentHostServiceLifecycleEvent>.Continuation?
        let stream = AsyncStream<AgentHostServiceLifecycleEvent> { streamContinuation in
            continuation = streamContinuation
            streamContinuation.onTermination = { [weak self] _ in
                Task { await self?.removeLifecycleSubscriber(id) }
            }
        }
        lifecycleContinuations[id] = continuation
        if let hello, clientGeneration > 0 {
            let event: AgentHostServiceLifecycleEvent = clientGeneration == 1
                ? .connected(generation: clientGeneration, hello: hello)
                : .restarted(generation: clientGeneration, hello: hello)
            continuation?.yield(event)
        }
        return stream
    }

    func start() async throws -> AgentHostHelloPayload {
        guard !isStopping else {
            throw AgentHostServiceError.stopped
        }
        if let hello {
            return hello
        }

        let task: Task<StartedAgentHost, Error>
        if let startupTask {
            task = startupTask
        } else {
            let executableURL = self.executableURL
            let arguments = self.arguments
            let environment = self.environment
            let requiredCapabilities = self.requiredCapabilities
            let handshakeTimeout = self.handshakeTimeout
            let newTask = Task {
                let candidate = AgentHostClient(
                    executableURL: executableURL,
                    arguments: arguments,
                    environment: environment,
                    handshakeTimeout: handshakeTimeout
                )
                return try await withTaskCancellationHandler(operation: {
                    let payload = try await candidate.start()
                    try Task.checkCancellation()
                    let missing = requiredCapabilities.subtracting(payload.capabilities).sorted()
                    guard missing.isEmpty else {
                        await candidate.stop()
                        throw AgentHostServiceError.missingCapabilities(missing)
                    }
                    return StartedAgentHost(client: candidate, hello: payload)
                }, onCancel: {
                    Task { await candidate.stop() }
                })
            }
            startupTask = newTask
            task = newTask
        }

        do {
            let started = try await task.value
            guard !isStopping else {
                await started.client.stop()
                startupTask = nil
                throw AgentHostServiceError.stopped
            }
            if client == nil {
                await install(started)
            }
            startupTask = nil
            return hello ?? started.hello
        } catch {
            startupTask = nil
            throw error
        }
    }

    private func install(_ started: StartedAgentHost) async {
        client = started.client
        hello = started.hello
        clientGeneration += 1
        let generation = clientGeneration
        let lifecycleEvent: AgentHostServiceLifecycleEvent = generation == 1
            ? .connected(generation: generation, hello: started.hello)
            : .restarted(generation: generation, hello: started.hello)
        for continuation in lifecycleContinuations.values {
            continuation.yield(lifecycleEvent)
        }
        let clientEvents = await started.client.events()
        eventForwardingTask = Task { [weak self] in
            for await event in clientEvents {
                await self?.forward(event)
            }
            await self?.clientEventStreamFinished(generation: generation)
        }
    }

    func request<Parameters: Encodable, Result: Decodable>(
        id: String = UUID().uuidString,
        method: String,
        params: Parameters,
        timeout: TimeInterval = 30,
        as responseType: Result.Type
    ) async throws -> Result {
        _ = try await start()
        guard let client else {
            throw AgentHostClientError.notRunning
        }
        return try await client.request(
            id: id,
            method: method,
            params: params,
            timeout: timeout,
            as: responseType
        )
    }

    func listSessions(
        cwd: String,
        sessionDirectory: String?,
        requestID: String = UUID().uuidString
    ) async throws -> [AgentHostSessionSummary] {
        let result: AgentHostSessionListResult = try await request(
            id: requestID,
            method: "sessions.list",
            params: AgentHostSessionListParameters(
                cwd: cwd,
                sessionDirectory: sessionDirectory
            ),
            as: AgentHostSessionListResult.self
        )
        return result.sessions
    }

    func listModels(
        requestID: String = UUID().uuidString
    ) async throws -> [AgentHostModel] {
        let result: AgentHostModelListResult = try await request(
            id: requestID,
            method: "models.list",
            params: AgentHostEmptyParameters(),
            as: AgentHostModelListResult.self
        )
        return result.models
    }

    func gitBranches(
        cwd: String,
        requestID: String = UUID().uuidString
    ) async throws -> AgentHostGitBranchesResult {
        try await request(
            id: requestID,
            method: "git.branches",
            params: AgentHostGitBranchesParameters(cwd: cwd),
            as: AgentHostGitBranchesResult.self
        )
    }

    func getAgentSettings(
        requestID: String = UUID().uuidString
    ) async throws -> AgentHostSettings {
        try await request(
            id: requestID,
            method: "settings.get",
            params: AgentHostEmptyParameters(),
            as: AgentHostSettings.self
        )
    }

    func updateAgentSettings(
        _ patch: AgentHostSettingsPatch,
        requestID: String = UUID().uuidString
    ) async throws -> AgentHostSettings {
        try await request(
            id: requestID,
            method: "settings.update",
            params: AgentHostSettingsUpdateParameters(patch: patch),
            as: AgentHostSettings.self
        )
    }

    func listInstalledExtensions(
        requestID: String = UUID().uuidString
    ) async throws -> [AgentHostInstalledExtensionPackage] {
        let result: AgentHostInstalledExtensionsResult = try await request(
            id: requestID,
            method: "extensions.listInstalled",
            params: AgentHostEmptyParameters(),
            as: AgentHostInstalledExtensionsResult.self
        )
        return result.packages
    }

    func getPiWebAccessConfiguration(
        requestID: String = UUID().uuidString
    ) async throws -> AgentHostPiWebAccessConfiguration {
        try await request(
            id: requestID,
            method: "extensions.piWebAccess.getConfiguration",
            params: AgentHostEmptyParameters(),
            as: AgentHostPiWebAccessConfiguration.self
        )
    }

    func updatePiWebAccessConfiguration(
        _ configuration: AgentHostPiWebAccessConfiguration,
        requestID: String = UUID().uuidString
    ) async throws -> AgentHostPiWebAccessConfiguration {
        try await request(
            id: requestID,
            method: "extensions.piWebAccess.updateConfiguration",
            params: configuration,
            as: AgentHostPiWebAccessConfiguration.self
        )
    }

    func installExtension(
        source: String,
        requestID: String = UUID().uuidString
    ) async throws -> [AgentHostInstalledExtensionPackage] {
        let result: AgentHostInstalledExtensionsResult = try await request(
            id: requestID,
            method: "extensions.install",
            params: AgentHostExtensionInstallParameters(source: source),
            timeout: 120,
            as: AgentHostInstalledExtensionsResult.self
        )
        return result.packages
    }

    func setInstalledExtensionEnabled(
        source: String,
        scope: AgentHostExtensionPackageScope,
        enabled: Bool,
        requestID: String = UUID().uuidString
    ) async throws -> [AgentHostInstalledExtensionPackage] {
        let result: AgentHostInstalledExtensionsResult = try await request(
            id: requestID,
            method: "extensions.setEnabled",
            params: AgentHostExtensionEnabledParameters(
                source: source,
                scope: scope,
                enabled: enabled
            ),
            as: AgentHostInstalledExtensionsResult.self
        )
        return result.packages
    }

    func updateInstalledExtension(
        source: String,
        scope: AgentHostExtensionPackageScope,
        requestID: String = UUID().uuidString
    ) async throws -> [AgentHostInstalledExtensionPackage] {
        let result: AgentHostInstalledExtensionsResult = try await request(
            id: requestID,
            method: "extensions.update",
            params: AgentHostExtensionPackageParameters(source: source, scope: scope),
            timeout: 120,
            as: AgentHostInstalledExtensionsResult.self
        )
        return result.packages
    }

    func removeInstalledExtension(
        source: String,
        scope: AgentHostExtensionPackageScope,
        requestID: String = UUID().uuidString
    ) async throws -> [AgentHostInstalledExtensionPackage] {
        let result: AgentHostInstalledExtensionsResult = try await request(
            id: requestID,
            method: "extensions.remove",
            params: AgentHostExtensionPackageParameters(source: source, scope: scope),
            timeout: 120,
            as: AgentHostInstalledExtensionsResult.self
        )
        return result.packages
    }

    func listProviders(
        requestID: String = UUID().uuidString
    ) async throws -> [AgentHostProvider] {
        let result: AgentHostProviderListResult = try await request(
            id: requestID,
            method: "providers.list",
            params: AgentHostEmptyParameters(),
            as: AgentHostProviderListResult.self
        )
        return result.providers
    }

    func startAuthentication(
        flowId: String,
        providerId: String,
        method: AgentHostAuthMethod,
        requestID: String = UUID().uuidString
    ) async throws -> AgentHostAuthStartResult {
        try await request(
            id: requestID,
            method: "auth.start",
            params: AgentHostAuthStartParameters(
                flowId: flowId,
                providerId: providerId,
                method: method
            ),
            as: AgentHostAuthStartResult.self
        )
    }

    func respondToAuthentication(
        flowId: String,
        promptId: String,
        value: String,
        requestID: String = UUID().uuidString
    ) async throws -> AgentHostAuthAcceptedResult {
        try await request(
            id: requestID,
            method: "auth.respond",
            params: AgentHostAuthRespondParameters(
                flowId: flowId,
                promptId: promptId,
                value: value
            ),
            as: AgentHostAuthAcceptedResult.self
        )
    }

    func cancelAuthentication(
        flowId: String,
        requestID: String = UUID().uuidString
    ) async throws -> AgentHostAuthCancelResult {
        try await request(
            id: requestID,
            method: "auth.cancel",
            params: AgentHostAuthCancelParameters(flowId: flowId),
            as: AgentHostAuthCancelResult.self
        )
    }

    func logoutProvider(
        providerId: String,
        requestID: String = UUID().uuidString
    ) async throws -> AgentHostAuthLogoutResult {
        try await request(
            id: requestID,
            method: "auth.logout",
            params: AgentHostAuthLogoutParameters(providerId: providerId),
            as: AgentHostAuthLogoutResult.self
        )
    }

    func createDraft(
        cwd: String,
        sessionDirectory: String?,
        profile: AgentHostSessionProfile,
        requestID: String = UUID().uuidString
    ) async throws -> AgentHostSessionSummary {
        let result: AgentHostSessionCreateDraftResult = try await request(
            id: requestID,
            method: "session.createDraft",
            params: AgentHostSessionCreateDraftParameters(
                cwd: cwd,
                sessionDirectory: sessionDirectory,
                profile: profile
            ),
            as: AgentHostSessionCreateDraftResult.self
        )
        return result.session
    }

    func openSession(
        path: String,
        sessionDirectory: String?,
        profile: AgentHostSessionProfile,
        requestID: String = UUID().uuidString
    ) async throws -> AgentHostSessionOpenResult {
        try await request(
            id: requestID,
            method: "session.open",
            params: AgentHostSessionOpenParameters(
                path: path,
                sessionDirectory: sessionDirectory,
                profile: profile
            ),
            as: AgentHostSessionOpenResult.self
        )
    }

    func snapshot(
        sessionId: String,
        requestID: String = UUID().uuidString
    ) async throws -> AgentHostSessionSnapshotResult {
        try await request(
            id: requestID,
            method: "session.snapshot",
            params: AgentHostSessionIdentifierParameters(sessionId: sessionId),
            as: AgentHostSessionSnapshotResult.self
        )
    }

    func toolOutput(
        sessionId: String,
        toolCallId: String,
        requestID: String = UUID().uuidString
    ) async throws -> AgentHostSessionToolOutputResult {
        try await request(
            id: requestID,
            method: "session.toolOutput",
            params: AgentHostSessionToolOutputParameters(
                sessionId: sessionId,
                toolCallId: toolCallId
            ),
            as: AgentHostSessionToolOutputResult.self
        )
    }

    func listSlashCommands(
        sessionId: String,
        requestID: String = UUID().uuidString
    ) async throws -> [AgentHostSlashCommand] {
        let result: AgentHostSlashCommandsResult = try await request(
            id: requestID,
            method: "session.commands",
            params: AgentHostSessionIdentifierParameters(sessionId: sessionId),
            as: AgentHostSlashCommandsResult.self
        )
        return result.commands
    }

    func renameSession(
        sessionId: String,
        title: String,
        requestID: String = UUID().uuidString
    ) async throws -> AgentHostSessionRenameResult {
        try await request(
            id: requestID,
            method: "session.rename",
            params: AgentHostSessionRenameParameters(sessionId: sessionId, title: title),
            as: AgentHostSessionRenameResult.self
        )
    }

    func setGitBranch(
        sessionId: String,
        branch: String,
        requestID: String = UUID().uuidString
    ) async throws -> AgentHostSessionSetGitBranchResult {
        try await request(
            id: requestID,
            method: "session.setGitBranch",
            params: AgentHostSessionSetGitBranchParameters(
                sessionId: sessionId,
                branch: branch
            ),
            as: AgentHostSessionSetGitBranchResult.self
        )
    }

    func setModel(
        sessionId: String,
        provider: String,
        modelId: String,
        requestID: String = UUID().uuidString
    ) async throws -> AgentHostSessionSetModelResult {
        try await request(
            id: requestID,
            method: "session.setModel",
            params: AgentHostSessionSetModelParameters(
                sessionId: sessionId,
                provider: provider,
                modelId: modelId
            ),
            as: AgentHostSessionSetModelResult.self
        )
    }

    func setModelOption(
        sessionId: String,
        option: AgentHostModelOption,
        enabled: Bool,
        requestID: String = UUID().uuidString
    ) async throws -> AgentHostSessionSetModelOptionResult {
        try await request(
            id: requestID,
            method: "session.setModelOption",
            params: AgentHostSessionSetModelOptionParameters(
                sessionId: sessionId,
                option: option,
                enabled: enabled
            ),
            as: AgentHostSessionSetModelOptionResult.self
        )
    }

    func setThinkingLevel(
        sessionId: String,
        thinkingLevel: AgentHostThinkingLevel,
        requestID: String = UUID().uuidString
    ) async throws -> AgentHostSessionSetThinkingLevelResult {
        try await request(
            id: requestID,
            method: "session.setThinkingLevel",
            params: AgentHostSessionSetThinkingLevelParameters(
                sessionId: sessionId,
                thinkingLevel: thinkingLevel
            ),
            as: AgentHostSessionSetThinkingLevelResult.self
        )
    }

    func setAccessMode(
        sessionId: String,
        accessMode: AgentHostAccessMode,
        requestID: String = UUID().uuidString
    ) async throws -> AgentHostSessionSetAccessModeResult {
        try await request(
            id: requestID,
            method: "session.setAccessMode",
            params: AgentHostSessionSetAccessModeParameters(
                sessionId: sessionId,
                accessMode: accessMode
            ),
            as: AgentHostSessionSetAccessModeResult.self
        )
    }

    func resolveApproval(
        sessionId: String,
        requestId: String,
        decision: AgentHostApprovalDecision,
        requestID: String = UUID().uuidString
    ) async throws -> AgentHostSessionResolveApprovalResult {
        try await request(
            id: requestID,
            method: "session.resolveApproval",
            params: AgentHostSessionResolveApprovalParameters(
                sessionId: sessionId,
                requestId: requestId,
                decision: decision
            ),
            as: AgentHostSessionResolveApprovalResult.self
        )
    }

    func prompt(
        sessionId: String,
        turnId: String,
        text: String,
        images: [AgentHostPromptImage] = [],
        requestID: String = UUID().uuidString
    ) async throws -> AgentHostSessionPromptResult {
        try await request(
            id: requestID,
            method: "session.prompt",
            params: AgentHostSessionPromptParameters(
                sessionId: sessionId,
                turnId: turnId,
                text: text,
                images: images
            ),
            as: AgentHostSessionPromptResult.self
        )
    }

    func abort(
        sessionId: String,
        requestID: String = UUID().uuidString
    ) async throws -> AgentHostSessionAbortResult {
        try await request(
            id: requestID,
            method: "session.abort",
            params: AgentHostSessionIdentifierParameters(sessionId: sessionId),
            as: AgentHostSessionAbortResult.self
        )
    }

    func closeSession(
        sessionId: String,
        requestID: String = UUID().uuidString
    ) async throws -> AgentHostSessionCloseResult {
        try await request(
            id: requestID,
            method: "session.close",
            params: AgentHostSessionIdentifierParameters(sessionId: sessionId),
            as: AgentHostSessionCloseResult.self
        )
    }

    func deleteSession(
        sessionId: String,
        cwd: String,
        sessionDirectory: String?,
        requestID: String = UUID().uuidString
    ) async throws -> AgentHostSessionDeleteResult {
        try await request(
            id: requestID,
            method: "session.delete",
            params: AgentHostSessionDeleteParameters(
                sessionId: sessionId,
                cwd: cwd,
                sessionDirectory: sessionDirectory
            ),
            as: AgentHostSessionDeleteResult.self
        )
    }

    func stop() async {
        isStopping = true
        startupTask?.cancel()
        startupTask = nil
        eventForwardingTask?.cancel()
        eventForwardingTask = nil
        if let client {
            await client.stop()
        }
        for continuation in eventContinuations.values {
            continuation.finish()
        }
        eventContinuations.removeAll()
        for continuation in lifecycleContinuations.values {
            continuation.finish()
        }
        lifecycleContinuations.removeAll()
        client = nil
        hello = nil
    }

    private func forward(_ event: AgentHostServerEvent) {
        for continuation in eventContinuations.values {
            continuation.yield(event)
        }
    }

    private func removeEventSubscriber(_ id: UUID) {
        eventContinuations[id] = nil
    }

    private func removeLifecycleSubscriber(_ id: UUID) {
        lifecycleContinuations[id] = nil
    }

    private func clientEventStreamFinished(generation: Int) async {
        guard generation == clientGeneration else { return }
        client = nil
        hello = nil
        eventForwardingTask = nil

        guard !isStopping else { return }
        let event = AgentHostServiceLifecycleEvent.disconnected(
            generation: generation,
            error: .connectionLost
        )
        for continuation in lifecycleContinuations.values {
            continuation.yield(event)
        }
        guard !automaticRecoveryAttempted else { return }
        automaticRecoveryAttempted = true
        _ = try? await start()
    }
}
