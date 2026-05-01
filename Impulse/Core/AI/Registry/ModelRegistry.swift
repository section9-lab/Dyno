import Foundation
import Combine

// MARK: - Featured Providers (offline fallback)

private let featuredProviders: [Provider] = [
    Provider(id: "ollama", name: "Ollama", baseURL: "http://127.0.0.1:11434/v1", envKeys: [], docURL: "https://docs.ollama.com"),
    Provider(id: "openai", name: "OpenAI", baseURL: "https://api.openai.com/v1", envKeys: ["OPENAI_API_KEY"], docURL: "https://platform.openai.com/docs/models"),
    Provider(id: "deepseek", name: "DeepSeek", baseURL: "https://api.deepseek.com/v1", envKeys: ["DEEPSEEK_API_KEY"], docURL: "https://api-docs.deepseek.com"),
    Provider(id: "anthropic", name: "Anthropic", baseURL: "https://api.anthropic.com/v1", envKeys: ["ANTHROPIC_API_KEY"], docURL: "https://docs.anthropic.com"),
    Provider(id: "zhipuai", name: "GLM / 智谱", baseURL: "https://open.bigmodel.cn/api/paas/v4", envKeys: ["ZAI_API_KEY"], docURL: "https://open.bigmodel.cn/dev/api"),
    Provider(id: "kimi-coding", name: "Kimi", baseURL: "https://api.moonshot.cn/v1", envKeys: ["KIMI_API_KEY"], docURL: "https://platform.moonshot.cn/docs"),
    Provider(id: "minimax", name: "MiniMax", baseURL: "https://api.minimax.chat/v1", envKeys: ["MINIMAX_API_KEY"], docURL: "https://platform.minimaxi.com/document"),
    Provider(id: "groq", name: "Groq", baseURL: "https://api.groq.com/openai/v1", envKeys: ["GROQ_API_KEY"], docURL: "https://console.groq.com/docs"),
    Provider(id: "mistral", name: "Mistral", baseURL: "https://api.mistral.ai/v1", envKeys: ["MISTRAL_API_KEY"], docURL: "https://docs.mistral.ai"),
    Provider(id: "xai", name: "xAI", baseURL: "https://api.x.ai/v1", envKeys: ["XAI_API_KEY"], docURL: "https://docs.x.ai"),
]

private let featuredProviderIDs = Set(featuredProviders.map(\.id))

// MARK: - ModelRegistry

@MainActor
final class ModelRegistry: ObservableObject {
    static let shared = ModelRegistry()

    @Published var providers: [Provider] = []
    @Published var isLoading = false

    // ModelInfo's custom `init(from:)` defaults missing fields, so adding
    // `inputModalities` is a forward-compatible schema change — old v1
    // blobs decode cleanly with `[.text]`. Keep the key on v1; bumping it
    // would empty the model list for offline users until the next refresh.
    private static let cacheKey = "modelregistry.modelsdev.cache.v1"
    private static let providersCacheKey = "modelregistry.modelsdev.providers.cache.v1"
    private static let customProvidersKey = "modelregistry.custom.providers.v1"
    private static let providerApiKeysKey = "modelregistry.apikeys.v1"

    private init() {
        loadProviders()
    }

    // MARK: - Public API

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        await fetchModelsdev()
        loadProviders()
    }

    func discoverLiveModels(for providerId: String) async {
        guard let index = providers.firstIndex(where: { $0.id == providerId }) else { return }
        let provider = providers[index]

        guard let baseURL = URL(string: provider.baseURL), !provider.baseURL.isEmpty else { return }

        let discovered = await fetchLiveModels(baseURL: baseURL, apiKey: provider.apiKey)
        guard !discovered.isEmpty else { return }

        // Merge: mark catalog models as live if discovered, add new discovered models
        var merged = providers[index].models
        var existingIDs = Set(merged.map(\.id))

        for i in merged.indices {
            if discovered.contains(where: { $0.id == merged[i].id }) {
                merged[i].isLive = true
            }
        }

        for model in discovered where !existingIDs.contains(model.id) {
            merged.append(model)
            existingIDs.insert(model.id)
        }

        // Sort: live first, then alphabetical
        merged.sort { a, b in
            if a.isLive != b.isLive { return a.isLive }
            return a.id < b.id
        }

        providers[index].models = merged
    }

    func setApiKey(_ key: String, for providerId: String) {
        guard let index = providers.firstIndex(where: { $0.id == providerId }) else { return }
        providers[index].apiKey = key
        saveApiKeys()
    }

    func addCustomProvider(name: String, baseURL: String, apiKey: String) {
        let id = "custom-\(UUID().uuidString.prefix(8).lowercased())"
        let provider = Provider(id: id, name: name, baseURL: baseURL, apiKey: apiKey, isCustom: true)
        providers.append(provider)
        saveCustomProviders()
        saveApiKeys()
    }

    func removeCustomProvider(_ providerId: String) {
        providers.removeAll { $0.id == providerId && $0.isCustom }
        saveCustomProviders()
    }

    func provider(for id: String) -> Provider? {
        providers.first { $0.id == id }
    }

    // MARK: - Load

    private func loadProviders() {
        // Start with featured providers
        var result = featuredProviders

        // Merge models.dev cached providers. Featured providers keep their local defaults.
        if let cachedProviders = loadModelsdevProvidersCache() {
            var existingIDs = Set(result.map(\.id))
            for provider in cachedProviders where !existingIDs.contains(provider.id) {
                guard !provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                result.append(provider)
                existingIDs.insert(provider.id)
            }
        } else if let cached = loadModelsdevCache() {
            for i in result.indices where cached[result[i].id] != nil {
                result[i].models = cached[result[i].id] ?? []
            }
        }

        if let cachedProviders = loadModelsdevProvidersCache() {
            let cachedByID = Dictionary(uniqueKeysWithValues: cachedProviders.map { ($0.id, $0) })
            for i in result.indices {
                guard let cached = cachedByID[result[i].id] else { continue }
                result[i].models = cached.models
                if result[i].envKeys.isEmpty {
                    result[i] = Provider(
                        id: result[i].id,
                        name: result[i].name,
                        baseURL: result[i].baseURL,
                        apiKey: result[i].apiKey,
                        envKeys: cached.envKeys,
                        docURL: result[i].docURL ?? cached.docURL,
                        models: result[i].models,
                        isCustom: result[i].isCustom
                    )
                }
            }
        }

        // Add custom providers
        result.append(contentsOf: loadCustomProviders())

        // Restore saved API keys
        let savedKeys = loadApiKeys()
        for i in result.indices {
            if let key = savedKeys[result[i].id], !key.isEmpty {
                result[i].apiKey = key
            }
        }

        // Check environment variables
        for i in result.indices {
            if result[i].apiKey.isEmpty {
                for envKey in result[i].envKeys {
                    if let value = ProcessInfo.processInfo.environment[envKey], !value.isEmpty {
                        result[i].apiKey = value
                        break
                    }
                }
            }
        }

        providers = result
    }

    // MARK: - models.dev

    private func fetchModelsdev() async {
        guard let url = URL(string: "https://models.dev/api.json") else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode)
        else { return }

        // Parse and cache
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        var modelCache: [String: [ModelInfo]] = [:]
        var providerCache: [Provider] = []

        for (providerId, rawProvider) in root {
            guard let providerObj = rawProvider as? [String: Any] else { continue }
            let apiURL = (providerObj["api"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !apiURL.isEmpty || featuredProviderIDs.contains(providerId) else { continue }

            let modelsObj = providerObj["models"] as? [String: [String: Any]] ?? [:]
            let models = parseModelsdevModels(modelsObj)
            let provider = Provider(
                id: (providerObj["id"] as? String) ?? providerId,
                name: (providerObj["name"] as? String) ?? providerId,
                baseURL: apiURL,
                envKeys: (providerObj["env"] as? [String]) ?? [],
                docURL: providerObj["doc"] as? String,
                models: models
            )

            providerCache.append(provider)
            modelCache[provider.id] = models
        }

        // Save cache
        if let encoded = try? JSONEncoder().encode(modelCache) {
            UserDefaults.standard.set(encoded, forKey: Self.cacheKey)
        }
        if let encoded = try? JSONEncoder().encode(providerCache.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
            UserDefaults.standard.set(encoded, forKey: Self.providersCacheKey)
        }
    }

    private func parseModelsdevModels(_ modelsObj: [String: [String: Any]]) -> [ModelInfo] {
        modelsObj.compactMap { (modelId, modelData) in
            let name = (modelData["name"] as? String) ?? modelId
            let toolCall = (modelData["tool_call"] as? Bool) ?? false
            let reasoning = (modelData["reasoning"] as? Bool) ?? false
            let limit = modelData["limit"] as? [String: Any]
            let contextWindow = (limit?["context"] as? Int)
            let modalities = modelData["modalities"] as? [String: [String]]
            let input = Self.parseModalities(modalities?["input"])
            return ModelInfo(
                id: modelId,
                name: name,
                toolCall: toolCall,
                reasoning: reasoning,
                contextWindow: contextWindow,
                inputModalities: input
            )
        }
        .sorted { $0.id < $1.id }
    }

    /// Map raw strings from models.dev (`["text", "image", ...]`) onto the
    /// `Modality` enum; unknown strings are dropped silently. Empty / nil
    /// input falls back to `[.text]` so we never persist an empty set
    /// (which the UI would treat as "no modalities at all").
    private static func parseModalities(_ raw: [String]?) -> Set<Modality> {
        guard let raw, !raw.isEmpty else { return [.text] }
        let parsed = raw.compactMap(Modality.init(rawValue:))
        return parsed.isEmpty ? [.text] : Set(parsed)
    }

    private func loadModelsdevCache() -> [String: [ModelInfo]]? {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey) else { return nil }
        return try? JSONDecoder().decode([String: [ModelInfo]].self, from: data)
    }

    private func loadModelsdevProvidersCache() -> [Provider]? {
        guard let data = UserDefaults.standard.data(forKey: Self.providersCacheKey) else { return nil }
        return try? JSONDecoder().decode([Provider].self, from: data)
    }

    // MARK: - Live Discovery

    private func fetchLiveModels(baseURL: URL, apiKey: String) async -> [ModelInfo] {
        let modelsURL = baseURL.appendingPathComponent("models")
        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode)
        else { return [] }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

        // OpenAI-compatible format: { "data": [{ "id": "..." }] }
        if let dataArray = root["data"] as? [[String: Any]] {
            return dataArray.compactMap { item in
                guard let id = item["id"] as? String else { return nil }
                return ModelInfo(id: id, name: id, toolCall: true, isLive: true)
            }
        }

        // Ollama format: { "models": [{ "name": "..." }] }
        if let modelsArray = root["models"] as? [[String: Any]] {
            return modelsArray.compactMap { item in
                guard let name = item["name"] as? String else { return nil }
                return ModelInfo(id: name, name: name, toolCall: true, isLive: true)
            }
        }

        return []
    }

    // MARK: - Custom Providers

    private func loadCustomProviders() -> [Provider] {
        guard let data = UserDefaults.standard.data(forKey: Self.customProvidersKey) else { return [] }
        return (try? JSONDecoder().decode([Provider].self, from: data)) ?? []
    }

    private func saveCustomProviders() {
        let custom = providers.filter(\.isCustom)
        if let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: Self.customProvidersKey)
        }
    }

    // MARK: - API Keys

    private func loadApiKeys() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: Self.providerApiKeysKey) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private func saveApiKeys() {
        var keys: [String: String] = [:]
        for provider in providers where !provider.apiKey.isEmpty {
            keys[provider.id] = provider.apiKey
        }
        if let data = try? JSONEncoder().encode(keys) {
            UserDefaults.standard.set(data, forKey: Self.providerApiKeysKey)
        }
    }
}
