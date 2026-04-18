import Foundation

struct AgentServiceConfig: Codable, Equatable {
    var providerId: String
    var baseURL: String
    var apiKey: String
    var modelId: String
    var workspace: String

    enum CodingKeys: String, CodingKey {
        case providerId, baseURL, apiKey, modelId, workspace
        case modelName, workdir, preset
    }

    init(providerId: String, baseURL: String, apiKey: String, modelId: String, workspace: String) {
        self.providerId = providerId
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelId = modelId
        self.workspace = workspace
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
        workspace =
            (try? container.decode(String.self, forKey: .workspace))
            ?? (try? container.decode(String.self, forKey: .workdir))
            ?? FileManager.default.homeDirectoryForCurrentUser.path
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(providerId, forKey: .providerId)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(apiKey, forKey: .apiKey)
        try container.encode(modelId, forKey: .modelId)
        try container.encode(workspace, forKey: .workspace)
    }
}
