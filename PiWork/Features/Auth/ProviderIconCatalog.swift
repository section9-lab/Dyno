import Foundation

enum ProviderIconCatalog {
    static func assetName(for providerID: String) -> String? {
        switch providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "amazon-bedrock":
            return "ModelIconBedrock"
        case "ant-ling":
            return "ModelIconAntGroup"
        case "anthropic", "cc-anthropic":
            return "ModelIconClaude"
        case "azure-openai-responses":
            return "ModelIconAzureAI"
        case "cerebras":
            return "ModelIconCerebras"
        case "cloudflare-ai-gateway", "cloudflare-workers-ai":
            return "ModelIconCloudflare"
        case "deepseek":
            return "ModelIconDeepSeek"
        case "fireworks":
            return "ModelIconFireworks"
        case "github-copilot":
            return "ModelIconCopilot"
        case "google":
            return "ModelIconGoogle"
        case "google-vertex":
            return "ModelIconVertexAI"
        case "groq":
            return "ModelIconGroq"
        case "huggingface":
            return "ModelIconHuggingFace"
        case "kimi-coding", "moonshotai", "moonshotai-cn":
            return "ModelIconKimi"
        case "minimax", "minimax-cn":
            return "ModelIconMiniMax"
        case "mistral":
            return "ModelIconMistral"
        case "nvidia":
            return "ModelIconNVIDIA"
        case "openai", "openai-codex", "cc-openai":
            return "ModelIconOpenAI"
        case "opencode", "opencode-go":
            return "ModelIconOpenCode"
        case "openrouter":
            return "ModelIconOpenRouter"
        case "qwen-token-plan", "qwen-token-plan-cn":
            return "ModelIconQwen"
        case "together":
            return "ModelIconTogether"
        case "vercel-ai-gateway":
            return "ModelIconVercel"
        case "xai":
            return "ModelIconXAI"
        case "xiaomi", "xiaomi-token-plan-ams", "xiaomi-token-plan-cn", "xiaomi-token-plan-sgp":
            return "ModelIconXiaomiMiMo"
        case "zai", "zai-coding-cn":
            return "ModelIconZAI"
        default:
            return nil
        }
    }
}
