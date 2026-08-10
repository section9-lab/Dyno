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
            "baseten": "ModelIconBaseten",
            "cerebras": "ModelIconCerebras",
            "cloudflare-ai-gateway": "ModelIconCloudflare",
            "cloudflare-workers-ai": "ModelIconCloudflare",
            "deepseek": "ModelIconDeepSeek",
            "fireworks": "ModelIconFireworks",
            "github-copilot": "ModelIconGitHubCopilot",
            "google": "ModelIconGoogle",
            "google-vertex": "ModelIconVertexAI",
            "groq": "ModelIconGroq",
            "huggingface": "ModelIconHuggingFace",
            "kimi-coding": "ModelIconKimiAvatar",
            "minimax": "ModelIconMiniMax",
            "minimax-cn": "ModelIconMiniMax",
            "mistral": "ModelIconMistral",
            "moonshotai": "ModelIconKimiAvatar",
            "moonshotai-cn": "ModelIconKimiAvatar",
            "nvidia": "ModelIconNVIDIA",
            "openai": "ModelIconOpenAI",
            "openai-codex": "ModelIconOpenAI",
            "cc-openai": "ModelIconOpenAI",
            "opencode": "ModelIconOpenCode",
            "opencode-go": "ModelIconOpenCode",
            "openrouter": "ModelIconOpenRouter",
            "qwen-token-plan": "ModelIconQwen",
            "qwen-token-plan-cn": "ModelIconQwen",
            "qwen-token-plan-individual": "ModelIconQwen",
            "radius": "ModelIconPi",
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
    }

    func testEveryMappedAssetExists() throws {
        let root = repositoryRoot()
        let assetNames = Set([
            "amazon-bedrock", "ant-ling", "anthropic", "azure-openai-responses", "baseten",
            "cerebras", "cloudflare-ai-gateway", "deepseek", "fireworks",
            "github-copilot", "google", "google-vertex", "groq", "huggingface",
            "kimi-coding", "minimax", "mistral", "nvidia", "openai", "opencode",
            "openrouter", "qwen-token-plan", "qwen-token-plan-individual", "radius",
            "together", "vercel-ai-gateway",
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

    func testGitHubCopilotUsesLobeHubGitHubCopilotSource() throws {
        XCTAssertEqual(
            ProviderIconCatalog.assetName(for: "github-copilot"),
            "ModelIconGitHubCopilot"
        )
        let svg = try svgSource(
            assetName: "ModelIconGitHubCopilot",
            filename: "githubcopilot.svg"
        )
        XCTAssertTrue(svg.contains("<title>GithubCopilot</title>"))
        XCTAssertFalse(svg.contains("<title>Copilot</title>"))
    }

    func testBasetenUsesLobeHubAvatarVariant() throws {
        XCTAssertEqual(ProviderIconCatalog.assetName(for: "baseten"), "ModelIconBaseten")
        let svg = try svgSource(assetName: "ModelIconBaseten", filename: "baseten-avatar.svg")
        XCTAssertTrue(svg.contains("fill=\"#19E76E\""))
        XCTAssertTrue(svg.contains("scale(.65)"))
    }

    func testKimiUsesLobeHubAvatarVariant() throws {
        XCTAssertEqual(
            ProviderIconCatalog.assetName(for: "kimi-coding"),
            "ModelIconKimiAvatar"
        )
        let svg = try svgSource(assetName: "ModelIconKimiAvatar", filename: "kimi-avatar.svg")
        XCTAssertTrue(svg.contains("fill=\"#000\""))
        XCTAssertTrue(svg.contains("scale(.6)"))
    }

    func testOpenRouterUsesLobeHubMonoSource() throws {
        let svg = try svgSource(assetName: "ModelIconOpenRouter", filename: "openrouter.svg")
        XCTAssertTrue(svg.contains("fill=\"currentColor\""))
    }

    func testRadiusUsesPiOfficialBadgeSource() throws {
        let assetName = ProviderIconCatalog.assetName(for: "radius")
        XCTAssertEqual(assetName, "ModelIconPi")
        guard assetName == "ModelIconPi" else { return }

        let imageSet = repositoryRoot()
            .appendingPathComponent("PiWork/Resources/Assets.xcassets/ModelIconPi.imageset")
        let contents = try String(
            contentsOf: imageSet.appendingPathComponent("Contents.json"),
            encoding: .utf8
        )
        XCTAssertTrue(contents.contains("\"filename\" : \"pi.svg\""))
        XCTAssertTrue(contents.contains("\"filename\" : \"pi-dark.svg\""))

        for filename in ["pi.svg", "pi-dark.svg"] {
            let svg = try String(
                contentsOf: imageSet.appendingPathComponent(filename),
                encoding: .utf8
            )
            XCTAssertTrue(svg.contains("<title>Pi</title>"))
            XCTAssertTrue(svg.contains("M165.29 165.29"))
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

    private func svgSource(assetName: String, filename: String) throws -> String {
        let imageSet = repositoryRoot()
            .appendingPathComponent("PiWork/Resources/Assets.xcassets")
            .appendingPathComponent("\(assetName).imageset")
        let contents = try String(
            contentsOf: imageSet.appendingPathComponent("Contents.json"),
            encoding: .utf8
        )
        XCTAssertTrue(contents.contains("\"filename\" : \"\(filename)\""))
        return try String(
            contentsOf: imageSet.appendingPathComponent(filename),
            encoding: .utf8
        )
    }
}
