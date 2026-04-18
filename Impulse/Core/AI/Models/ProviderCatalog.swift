import Foundation

struct ModelInfo: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let name: String
    var toolCall: Bool
    var reasoning: Bool
    var contextWindow: Int?
    var isLive: Bool

    init(id: String, name: String = "", toolCall: Bool = true, reasoning: Bool = false, contextWindow: Int? = nil, isLive: Bool = false) {
        self.id = id
        self.name = name.isEmpty ? id : name
        self.toolCall = toolCall
        self.reasoning = reasoning
        self.contextWindow = contextWindow
        self.isLive = isLive
    }
}

struct Provider: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    var baseURL: String
    var apiKey: String
    let envKeys: [String]
    let docURL: String?
    var models: [ModelInfo]
    var isCustom: Bool

    init(id: String, name: String, baseURL: String, apiKey: String = "", envKeys: [String] = [], docURL: String? = nil, models: [ModelInfo] = [], isCustom: Bool = false) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.envKeys = envKeys
        self.docURL = docURL
        self.models = models
        self.isCustom = isCustom
    }
}
