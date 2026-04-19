import Foundation

struct AgentServiceConfig: Codable, Equatable {
    var providerId: String
    var baseURL: String
    var apiKey: String
    var modelId: String
    var agentHomeDirectory: String
    var projectDirectory: String

    private static var defaultAppSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    static var defaultAgentHomeDirectoryPath: String {
        defaultAppSupportDirectory
            .appendingPathComponent("Impulse", isDirectory: true)
            .appendingPathComponent(".agent", isDirectory: true)
            .path
    }

    static var defaultExecutionWorkspacePath: String {
        defaultAppSupportDirectory
            .appendingPathComponent("Impulse", isDirectory: true)
            .appendingPathComponent("workspace", isDirectory: true)
            .path
    }

    enum CodingKeys: String, CodingKey {
        case providerId, baseURL, apiKey, modelId
        case agentHomeDirectory, projectDirectory
        case sandboxDirectory, workspace
        case modelName, workdir, preset
    }

    init(
        providerId: String,
        baseURL: String,
        apiKey: String,
        modelId: String,
        agentHomeDirectory: String = Self.defaultAgentHomeDirectoryPath,
        projectDirectory: String = ""
    ) {
        self.providerId = providerId
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelId = modelId
        self.agentHomeDirectory = agentHomeDirectory
        self.projectDirectory = projectDirectory
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

        let legacyProjectDirectory =
            (try? container.decode(String.self, forKey: .sandboxDirectory))
            ?? (try? container.decode(String.self, forKey: .workspace))
            ?? (try? container.decode(String.self, forKey: .workdir))
            ?? ""

        agentHomeDirectory =
            (try? container.decode(String.self, forKey: .agentHomeDirectory))
            ?? Self.defaultAgentHomeDirectoryPath
        projectDirectory =
            (try? container.decode(String.self, forKey: .projectDirectory))
            ?? legacyProjectDirectory
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(providerId, forKey: .providerId)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(apiKey, forKey: .apiKey)
        try container.encode(modelId, forKey: .modelId)
        try container.encode(agentHomeDirectory, forKey: .agentHomeDirectory)
        try container.encode(projectDirectory, forKey: .projectDirectory)
    }
}
