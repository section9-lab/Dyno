import Foundation

/// Input/output modality a model accepts or emits. Raw values match the
/// strings emitted by models.dev's `modalities.input` / `modalities.output`
/// so JSON parsing is a direct `init(rawValue:)`.
///
/// `allCases` order is the canonical display order used by the UI — keep
/// `text` first so it sorts naturally when rendered, even though the
/// capability badge view filters it out.
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
    /// Modalities the model accepts as input. Defaults to `[.text]` for
    /// live-discovered models (their endpoints don't expose this) and for
    /// any models.dev entry that omits the field.
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

    /// Custom decoder so older cached `ModelInfo` blobs (which predate the
    /// modality field) decode cleanly with `[.text]` as the default rather
    /// than failing the whole provider cache load.
    private enum CodingKeys: String, CodingKey {
        case id, name, toolCall, reasoning, contextWindow, isLive
        case inputModalities
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.toolCall = try c.decodeIfPresent(Bool.self, forKey: .toolCall) ?? true
        self.reasoning = try c.decodeIfPresent(Bool.self, forKey: .reasoning) ?? false
        self.contextWindow = try c.decodeIfPresent(Int.self, forKey: .contextWindow)
        self.isLive = try c.decodeIfPresent(Bool.self, forKey: .isLive) ?? false
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
