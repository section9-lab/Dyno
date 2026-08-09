import XCTest
@testable import PiWork

final class ProviderIconCatalogTests: XCTestCase {
    func testBuiltInProvidersAndKnownAliasesMapToBrandAssets() {
        let expectations = [
            "amazon-bedrock": "ModelIconBedrock",
            "ant-ling": "ModelIconAntGroup",
            "anthropic": "ModelIconClaude",
            "cc-anthropic": "ModelIconClaude",
            "azure-openai-responses": "ModelIconAzureAI",
            "cerebras": "ModelIconCerebras",
            "cloudflare-ai-gateway": "ModelIconCloudflare",
            "cloudflare-workers-ai": "ModelIconCloudflare",
            "deepseek": "ModelIconDeepSeek",
            "fireworks": "ModelIconFireworks",
            "github-copilot": "ModelIconCopilot",
            "google": "ModelIconGoogle",
            "google-vertex": "ModelIconVertexAI",
            "groq": "ModelIconGroq",
            "huggingface": "ModelIconHuggingFace",
            "kimi-coding": "ModelIconKimi",
            "minimax": "ModelIconMiniMax",
            "minimax-cn": "ModelIconMiniMax",
            "mistral": "ModelIconMistral",
            "moonshotai": "ModelIconKimi",
            "moonshotai-cn": "ModelIconKimi",
            "nvidia": "ModelIconNVIDIA",
            "openai": "ModelIconOpenAI",
            "openai-codex": "ModelIconOpenAI",
            "cc-openai": "ModelIconOpenAI",
            "opencode": "ModelIconOpenCode",
            "opencode-go": "ModelIconOpenCode",
            "openrouter": "ModelIconOpenRouter",
            "qwen-token-plan": "ModelIconQwen",
            "qwen-token-plan-cn": "ModelIconQwen",
            "together": "ModelIconTogether",
            "vercel-ai-gateway": "ModelIconVercel",
            "xai": "ModelIconXAI",
            "xiaomi": "ModelIconXiaomiMiMo",
            "xiaomi-token-plan-ams": "ModelIconXiaomiMiMo",
            "xiaomi-token-plan-cn": "ModelIconXiaomiMiMo",
            "xiaomi-token-plan-sgp": "ModelIconXiaomiMiMo",
            "zai": "ModelIconZAI",
            "zai-coding-cn": "ModelIconZAI",
        ]

        for (providerID, assetName) in expectations {
            XCTAssertEqual(
                ProviderIconCatalog.assetName(for: providerID),
                assetName,
                "Unexpected icon for \(providerID)"
            )
        }
    }

    func testUnknownProviderKeepsFallbackInsteadOfClaimingAnotherBrand() {
        XCTAssertNil(ProviderIconCatalog.assetName(for: "my-private-provider"))
        XCTAssertNil(ProviderIconCatalog.assetName(for: "radius"))
    }

    func testEveryMappedAssetExists() throws {
        let root = repositoryRoot()
        let assetNames = Set([
            "amazon-bedrock", "ant-ling", "anthropic", "azure-openai-responses",
            "cerebras", "cloudflare-ai-gateway", "deepseek", "fireworks",
            "github-copilot", "google", "google-vertex", "groq", "huggingface",
            "kimi-coding", "minimax", "mistral", "nvidia", "openai", "opencode",
            "openrouter", "qwen-token-plan", "together", "vercel-ai-gateway",
            "xai", "xiaomi", "zai",
        ].compactMap(ProviderIconCatalog.assetName(for:)))

        for assetName in assetNames {
            let imageSet = root
                .appendingPathComponent("PiWork/Resources/Assets.xcassets")
                .appendingPathComponent("\(assetName).imageset")
            let contentsURL = imageSet.appendingPathComponent("Contents.json")
            XCTAssertTrue(FileManager.default.fileExists(atPath: contentsURL.path))
        }
    }

    func testProvidersWithColorVariantsUseLobeHubColorSources() throws {
        let expectedSources = [
            "ModelIconMiniMax": "minimax-color.svg",
            "ModelIconMistral": "mistral-color.svg",
            "ModelIconNVIDIA": "nvidia-color.svg",
            "ModelIconQwen": "qwen-color.svg",
        ]

        for (assetName, filename) in expectedSources {
            let contentsURL = repositoryRoot()
                .appendingPathComponent("PiWork/Resources/Assets.xcassets")
                .appendingPathComponent("\(assetName).imageset/Contents.json")
            let contents = try String(contentsOf: contentsURL, encoding: .utf8)

            XCTAssertTrue(
                contents.contains("\"filename\" : \"\(filename)\""),
                "\(assetName) must use LobeHub's original color source"
            )
        }
    }

    func testAuthenticationRowRequestsOriginalRenderingAndRetainsInitialFallback() throws {
        let sourceURL = repositoryRoot()
            .appendingPathComponent("PiWork/Features/Auth/Views/ModelProviderSettingsView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("ProviderIconCatalog.assetName(for: provider.id)"))
        XCTAssertTrue(source.contains(".renderingMode(.original)"))
        XCTAssertTrue(source.contains("Text(String(provider.name.prefix(1)).uppercased())"))
    }

    func testOnboardingGoogleButtonUsesLobeHubColorAsset() throws {
        let sourceURL = repositoryRoot()
            .appendingPathComponent("PiWork/Features/Auth/Views/OnboardingLoginView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let glyphStart = try XCTUnwrap(source.range(of: "private struct GoogleGlyph"))
        let glyphSource = source[glyphStart.lowerBound...]

        XCTAssertTrue(glyphSource.contains("Image(\"ModelIconGoogle\")"))
        XCTAssertTrue(glyphSource.contains(".renderingMode(.original)"))
        XCTAssertFalse(glyphSource.contains("Text(\"G\")"))
        XCTAssertFalse(glyphSource.contains("LinearGradient("))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
