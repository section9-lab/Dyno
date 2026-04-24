import Foundation

struct AgentServiceConfig: Codable, Equatable {
    var providerId: String
    var baseURL: String
    var apiKey: String
    var modelId: String

    static var defaultAppSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    static var defaultStorageDirectoryPath: String {
        defaultAppSupportDirectory
            .appendingPathComponent("Impulse", isDirectory: true)
            .path
    }

    static var defaultExecutionWorkspacePath: String {
        URL(fileURLWithPath: defaultStorageDirectoryPath)
            .appendingPathComponent("workspace", isDirectory: true)
            .path
    }

    enum CodingKeys: String, CodingKey {
        case providerId, baseURL, apiKey, modelId
        case sandboxDirectory, workspace
        case modelName, workdir, preset
    }

    init(
        providerId: String,
        baseURL: String,
        apiKey: String,
        modelId: String
    ) {
        self.providerId = providerId
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelId = modelId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providerId = (try? container.decode(String.self, forKey: .providerId))
            ?? (try? container.decode(String.self, forKey: .preset))
            ?? "ollama"
        baseURL = try container.decode(String.self, forKey: .baseURL)
        apiKey = try container.decode(String.self, forKey: .apiKey)
        modelId = (try? container.decode(String.self, forKey: .modelId))
            ?? (try? container.decode(String.self, forKey: .modelName))
            ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(providerId, forKey: .providerId)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(apiKey, forKey: .apiKey)
        try container.encode(modelId, forKey: .modelId)
    }
}
