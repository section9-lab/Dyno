import Foundation

/// Owns the persisted `AgentServiceConfig`. Knows the storage key, the legacy
/// fallback keys (v1/v2 → v3), and how to derive a default from environment
/// variables. Pure value-store; does not know about SDKs or sessions.
struct AgentConfigStore {
    private static let currentKey = "agent.service.config.v3"
    private static let legacyKeys = [
        "agent.service.config.v2",
        "agent.service.config.v1"
    ]

    private let defaults: UserDefaults

    /// Inject a non-standard `UserDefaults` for tests; in production callers
    /// pass nothing and we use `.standard`.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Loads from current key, falling back to legacy keys. Returns
    /// environment-derived default if nothing is stored.
    func load() -> AgentServiceConfig {
        if let stored = readStored() {
            return stored
        }
        return Self.defaultFromEnvironment()
    }

    func save(_ config: AgentServiceConfig) {
        do {
            let data = try JSONEncoder().encode(config)
            defaults.set(data, forKey: Self.currentKey)
        } catch {
            AppLog.persistence.error("Failed to encode AgentServiceConfig: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func readStored() -> AgentServiceConfig? {
        let allKeys = [Self.currentKey] + Self.legacyKeys
        for key in allKeys {
            guard let data = defaults.data(forKey: key) else { continue }
            do {
                return try JSONDecoder().decode(AgentServiceConfig.self, from: data)
            } catch {
                AppLog.persistence.error("Failed to decode AgentServiceConfig at key \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return nil
    }

    static func defaultFromEnvironment() -> AgentServiceConfig {
        let base = ProcessInfo.processInfo.environment["OPENAI_BASE_URL"] ?? "http://127.0.0.1:11434/v1"
        let model = ProcessInfo.processInfo.environment["OPENAI_MODEL"]
            ?? ProcessInfo.processInfo.environment["OLLAMA_MODEL"]
            ?? ""
        let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
        let providerId = base.contains("11434") ? "ollama" : "custom"
        return AgentServiceConfig(
            providerId: providerId,
            baseURL: base,
            apiKey: key,
            modelId: model
        )
    }
}
