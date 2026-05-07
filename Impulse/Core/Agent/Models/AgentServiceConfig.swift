import Foundation

struct AgentServiceConfig: Codable, Equatable {
    var providerId: String
    var baseURL: String
    var apiKey: String
    var modelId: String
    /// Wire protocol the SDK should speak. Routed on by `AgentSDKFactory`
    /// to choose between OpenAI Chat Completions vs Anthropic Messages.
    /// Always populated when the config is built from a `Provider` —
    /// callers should pass `provider.apiKind`.
    var apiKind: ApiKind

    static var defaultAppSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
    }

    static var defaultAppDataDirectoryPath: String {
        defaultAppSupportDirectory
            .appendingPathComponent("Impulse", isDirectory: true)
            .path
    }

    static var defaultStorageDirectoryPath: String {
        defaultAppDataDirectoryPath
    }

    static var defaultExecutionWorkspacePath: String {
        URL(fileURLWithPath: defaultAppDataDirectoryPath)
            .appendingPathComponent("workspace", isDirectory: true)
            .path
    }

    init(
        providerId: String,
        baseURL: String,
        apiKey: String,
        modelId: String,
        apiKind: ApiKind
    ) {
        self.providerId = providerId
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelId = modelId
        self.apiKind = apiKind
    }
}
