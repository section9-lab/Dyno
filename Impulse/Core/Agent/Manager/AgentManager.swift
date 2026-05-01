import Foundation
import Combine
import SwiftUI
import SwiftCodingAgent

/// Facade over the agent runtime subsystems. Composes:
///   - `AgentConfigStore`     — UserDefaults persistence for `AgentServiceConfig`
///   - `AgentRuntimeBootstrap` — disk layout (data/skills/memory dirs + legacy migration)
///   - `AgentSDKFactory`      — pure SDK builder (per-session)
///   - `SessionAgentPool`     — per-session pool + LRU + pending-config-rebuild
///   - `ModelRegistry`        — provider/model catalog (shared)
///
/// Holds connection-status `@Published` state so views can observe a single
/// object, and re-exposes pool methods so existing callers (`ChatViewModel`,
/// `ContentView`) don't need to be rewritten.
@MainActor
final class AgentManager: ObservableObject {
    static let shared = AgentManager()

    // MARK: - Public observable state

    @Published var isServiceConnected: Bool = false
    @Published var connectionStatusText: String = L10n.tr("agent.status.checking")
    @Published var config: AgentServiceConfig
    @Published private(set) var activeProjectPath: String?

    // MARK: - Subsystems

    let registry = ModelRegistry.shared
    private let configStore = AgentConfigStore()
    private let bootstrap = AgentRuntimeBootstrap()
    let pool: SessionAgentPool

    // Forwarded for compatibility with existing call sites.
    var sessionAgents: [String: SessionAgent] { pool.sessionAgents }
    var focusedSessionID: String? {
        get { pool.focusedSessionID }
        set { pool.focusedSessionID = newValue }
    }

    // MARK: - Static directory accessors (still referenced by views/settings)

    static var storageDirectoryURL: URL {
        URL(fileURLWithPath: AgentServiceConfig.defaultStorageDirectoryPath)
    }
    var storageDirectoryURL: URL { Self.storageDirectoryURL }
    static var appDataDirectoryURL: URL {
        URL(fileURLWithPath: AgentServiceConfig.defaultAppDataDirectoryPath)
    }
    private static var defaultExecutionWorkspaceURL: URL {
        URL(fileURLWithPath: AgentServiceConfig.defaultExecutionWorkspacePath)
    }

    // MARK: - Project path conveniences

    var activeProjectDirectoryURL: URL? {
        let path = (activeProjectPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    var executionWorkingDirectoryURL: URL {
        activeProjectDirectoryURL ?? Self.defaultExecutionWorkspaceURL
    }

    // MARK: - Init

    private init() {
        let initialConfig = configStore.load()
        self.config = initialConfig

        // Two-phase init: pool needs `self.config` to call the SDK factory.
        // Capture the manager weakly through the closure to avoid retain cycle.
        var poolFactoryRef: ((String) -> AgentSDK)?
        self.pool = SessionAgentPool { projectPath in
            poolFactoryRef!(projectPath)
        }
        poolFactoryRef = { [unowned self] projectPath in
            AgentSDKFactory.make(
                config: self.config,
                activeProjectPath: projectPath,
                storageDirectoryURL: Self.storageDirectoryURL,
                defaultExecutionWorkspaceURL: Self.defaultExecutionWorkspaceURL,
                sandboxRoots: SandboxAccessManager.shared.authorizedRoots
            )
        }

        registry.setApiKey(initialConfig.apiKey, for: initialConfig.providerId)
        bootstrap.bootstrap()

        Task {
            await registry.refresh()
            await self.refreshServiceStatus()
        }
    }

    // MARK: - Config

    func applyConfig(_ newConfig: AgentServiceConfig) async {
        config = newConfig
        registry.setApiKey(newConfig.apiKey, for: newConfig.providerId)
        configStore.save(newConfig)
        bootstrap.bootstrap()
        pool.refreshAllSDKs()
        await refreshServiceStatus()
    }

    /// Rebuild every *idle* SessionAgent's SDK (e.g. sandbox roots changed).
    /// In-flight sessions are queued and rebuilt when they next become idle.
    func refreshRuntimeContext() {
        bootstrap.bootstrap()
        pool.refreshAllSDKs()
    }

    // MARK: - Active project

    func setActiveProjectPath(_ path: String?) {
        let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPath = (trimmed?.isEmpty == false) ? trimmed : nil
        guard activeProjectPath != normalizedPath else { return }
        activeProjectPath = normalizedPath
    }

    // MARK: - Session pool (forwarding)

    @discardableResult
    func sessionAgent(for sessionID: String, projectPath: String) -> SessionAgent {
        pool.sessionAgent(for: sessionID, projectPath: projectPath)
    }

    func existingSessionAgent(for sessionID: String?) -> SessionAgent? {
        pool.existingSessionAgent(for: sessionID)
    }

    func discardSessionAgent(for sessionID: String) {
        pool.discardSessionAgent(for: sessionID)
    }

    func resetSessionAgent(for sessionID: String, projectPath: String) {
        pool.resetSessionAgent(for: sessionID, projectPath: projectPath)
    }

    func applyPendingConfigRebuild(for sessionID: String) {
        pool.applyPendingConfigRebuild(for: sessionID)
    }

    var isAnySessionResponding: Bool { pool.isAnyResponding }

    // MARK: - Connection status

    func refreshServiceStatus() async {
        connectionStatusText = L10n.tr("agent.status.checking")

        guard !config.baseURL.isEmpty else {
            isServiceConnected = false
            connectionStatusText = L10n.tr("agent.status.base_url_missing")
            return
        }

        await registry.discoverLiveModels(for: config.providerId)

        let provider = registry.provider(for: config.providerId)
        let liveModels = provider?.models.filter(\.isLive) ?? []

        if liveModels.isEmpty {
            await probeViaModelsEndpoint()
            return
        }

        isServiceConnected = true
        let found = liveModels.contains { $0.id == config.modelId }
        connectionStatusText = found
            ? L10n.tr("agent.status.connected", config.modelId)
            : L10n.tr("agent.status.connected_missing_model", liveModels.count, config.modelId)
    }

    private func probeViaModelsEndpoint() async {
        guard let baseURL = URL(string: config.baseURL) else {
            isServiceConnected = false
            connectionStatusText = L10n.tr("agent.status.base_url_invalid")
            return
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.httpMethod = "GET"
        request.timeoutInterval = 6
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                isServiceConnected = true
                connectionStatusText = L10n.tr("agent.status.connected", config.modelId)
            } else {
                isServiceConnected = false
                connectionStatusText = L10n.tr("agent.status.service_unavailable")
            }
        } catch {
            isServiceConnected = false
            connectionStatusText = L10n.tr("agent.status.connection_failed", error.localizedDescription)
        }
    }
}
