import Foundation

/// Raw values match the strings emitted by models.dev's
/// `modalities.input` / `modalities.output` so parsing is a direct
/// `init(rawValue:)`. `allCases` order doubles as the UI display order;
/// reorder cases at your peril.
enum Modality: String, Codable, CaseIterable, Hashable {
    case text
    case image
    case audio
    case video
}

struct ModelInfo: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let name: String
    var toolCall: Bool
    var reasoning: Bool
    var contextWindow: Int?
    var isLive: Bool
    /// Defaults to `[.text]` for live-discovered models (their endpoints
    /// don't expose this) and for models.dev entries that omit the field.
    var inputModalities: Set<Modality>

    init(
        id: String,
        name: String = "",
        toolCall: Bool = true,
        reasoning: Bool = false,
        contextWindow: Int? = nil,
        isLive: Bool = false,
        inputModalities: Set<Modality> = [.text]
    ) {
        self.id = id
        self.name = name.isEmpty ? id : name
        self.toolCall = toolCall
        self.reasoning = reasoning
        self.contextWindow = contextWindow
        self.isLive = isLive
        self.inputModalities = inputModalities
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, toolCall, reasoning, contextWindow, isLive
        case inputModalities
    }

    /// True iff the model can be reached through one of the four
    /// chat-completion-style protocols this app supports — `@ai-sdk/openai`,
    /// `@ai-sdk/openai-compatible`, `@ai-sdk/anthropic`, `@ai-sdk/google`.
    /// `/v1/models` listings (and models.dev) include embeddings, TTS,
    /// transcription, image generation, moderation, and rerankers that
    /// share the same listing endpoint but cannot be hit through Chat
    /// Completions / Messages / generateContent. Filtering by id pattern
    /// is brittle but covers the major providers' naming conventions and
    /// stays correct as new chat models ship.
    var isChatCompatible: Bool {
        let lower = id.lowercased()
        let blocklist = [
            "embedding", "embed-",
            "tts", "whisper", "transcrib", "speech",
            "moderation", "guard",
            "rerank",
            "dall-e", "dalle", "gpt-image",
            "imagen", "veo",
            "stable-diffusion",
        ]
        return !blocklist.contains(where: lower.contains)
    }

    /// Custom decoder so cached blobs from before `inputModalities` was
    /// added still load — the rest of the fields are required.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.toolCall = try c.decode(Bool.self, forKey: .toolCall)
        self.reasoning = try c.decode(Bool.self, forKey: .reasoning)
        self.contextWindow = try c.decodeIfPresent(Int.self, forKey: .contextWindow)
        self.isLive = try c.decode(Bool.self, forKey: .isLive)
        self.inputModalities = try c.decodeIfPresent(Set<Modality>.self, forKey: .inputModalities) ?? [.text]
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
    /// Wire protocol used when talking to this provider. Required field;
    /// every featured/cached/custom provider must declare one. When the
    /// caller doesn't know (e.g. parsing models.dev or building a custom
    /// provider from a base URL), use `ApiKind.sniff(baseURL:)` to pick.
    var apiKind: ApiKind

    init(id: String, name: String, baseURL: String, apiKey: String = "", envKeys: [String] = [], docURL: String? = nil, models: [ModelInfo] = [], isCustom: Bool = false, apiKind: ApiKind) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.envKeys = envKeys
        self.docURL = docURL
        self.models = models
        self.isCustom = isCustom
        self.apiKind = apiKind
    }
}
