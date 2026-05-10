import Foundation

/// Wire-protocol the SDK should speak to a given provider.
///
/// We intentionally separate "protocol" (this enum) from "provider" (the
/// `Provider.id` string). One protocol covers many providers — most of
/// today's hosted chat APIs are OpenAI-compatible — while a single
/// provider can occasionally expose multiple protocols (e.g. OpenRouter
/// also speaks the Anthropic shape on a different path). Borrowed from
/// pi-mono's `Api` field on `Model`, which decouples the two cleanly.
///
/// Add a new case here when wiring up a brand-new wire format
/// (Bedrock, Vertex, …). Routing in `AgentSDKFactory` and the
/// connectivity probe in the settings view both switch on this.
enum ApiKind: String, Codable, Hashable, CaseIterable {
    /// OpenAI Chat Completions (`POST /chat/completions`, `Authorization: Bearer …`).
    /// Default for the vast majority of providers — DeepSeek, Groq, xAI,
    /// Moonshot, Ollama, OpenRouter, GLM, MiniMax, …
    case openAICompletions

    /// Anthropic Messages API (`POST /messages`, `x-api-key` header,
    /// `anthropic-version` header, `tool_use`/`tool_result` blocks).
    /// Used when talking to api.anthropic.com directly. Going through a
    /// proxy that exposes the Anthropic shape (e.g. some Bedrock proxies)
    /// counts too.
    case anthropicMessages

    /// Google Generative Language API (`POST /v1beta/models/{model}:generateContent`,
    /// `x-goog-api-key` header). Routed to `GoogleGenerativeAIClient`. Vertex AI
    /// is intentionally out of scope — its auth and URL shape differ.
    case googleGenerativeLanguage

    /// User-facing label for settings UI / debugging.
    var displayName: String {
        switch self {
        case .openAICompletions: return "OpenAI Chat Completions"
        case .anthropicMessages: return "Anthropic Messages"
        case .googleGenerativeLanguage: return "Gemini Generative Language"
        }
    }
}

extension ApiKind {
    /// Heuristic fallback when neither the provider catalog nor a stored
    /// config explicitly carries an `apiKind`. Conservative on purpose:
    /// only flips to `.anthropicMessages` when the host is unmistakably
    /// Anthropic. Any other URL — including OpenAI-compatible proxies in
    /// front of Claude (OpenRouter, LiteLLM, custom gateways) — stays on
    /// `.openAICompletions`, which is what those proxies actually speak.
    static func sniff(baseURL: String) -> ApiKind {
        guard let host = URL(string: baseURL)?.host?.lowercased() else {
            return .openAICompletions
        }
        if host == "api.anthropic.com" || host.hasSuffix(".anthropic.com") {
            return .anthropicMessages
        }
        if host == "generativelanguage.googleapis.com" || host.hasSuffix(".generativelanguage.googleapis.com") {
            return .googleGenerativeLanguage
        }
        return .openAICompletions
    }

    /// Heuristic from a model id alone. Useful when a single base URL
    /// fronts multiple wire formats — e.g. a relay that exposes both
    /// `gpt-4o` (OpenAI shape) and `claude-opus-4-7` (Anthropic shape) on
    /// the same host. Returns `nil` when no signal is strong enough; the
    /// caller should fall back to the provider's `apiKind` or
    /// `sniff(baseURL:)` in that case.
    ///
    /// Matches against the bare segment after any vendor prefix
    /// ("anthropic/claude-...", "models/gemini-...") so namespaced ids
    /// don't dodge the match.
    static func sniff(modelId: String) -> ApiKind? {
        let lower = modelId.lowercased()
        let bare = lower.split(separator: "/").last.map(String.init) ?? lower

        if bare.hasPrefix("claude-")
            || bare.hasPrefix("claude.")
            || lower.hasPrefix("anthropic/")
            || lower.hasPrefix("anthropic.") {
            return .anthropicMessages
        }
        if bare.hasPrefix("gemini-")
            || bare.hasPrefix("gemini.")
            || lower.hasPrefix("google/gemini")
            || lower.hasPrefix("models/gemini") {
            return .googleGenerativeLanguage
        }
        return nil
    }
}
