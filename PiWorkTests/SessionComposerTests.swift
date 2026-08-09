import AppKit
import SwiftUI
import XCTest
@testable import PiWork

final class SessionComposerTests: XCTestCase {
    func testHostMessageProjectionPreservesIdentityAndVisibleContent() {
        let source = AgentHostSessionMessage(
            id: "message-one",
            role: .assistant,
            content: [
                .text("完成"),
                .image(mimeType: "image/png"),
                .toolCall(id: "tool-one", name: "read", argumentsSummary: "README.md")
            ],
            timestamp: "2026-08-09T00:00:00.000Z",
            provider: "openai",
            model: "gpt-test",
            stopReason: nil,
            errorMessage: nil,
            toolCallId: nil,
            toolName: nil,
            isError: nil
        )

        let message = PiChatMessage(message: source, isStreaming: true)

        XCTAssertEqual(message.id, "message-one")
        XCTAssertEqual(message.role, .assistant)
        XCTAssertEqual(
            message.text,
            "完成\n\(L10n.format("chat.image_attachment", "image/png"))\n▶ read README.md"
        )
        XCTAssertTrue(message.isStreaming)
    }

    func testTranscriptProjectionPreservesStructuredContentParts() {
        let tool = SessionToolRecord(
            id: "tool-one",
            name: "read",
            summary: #"{"path":"README.md"}"#,
            output: "README contents",
            state: .completed,
            isError: false
        )
        let source = SessionTranscriptMessage(
            id: "assistant-one",
            role: .assistant,
            parts: [
                .text(id: "text-before", text: "**Before**"),
                .tool(tool),
                .text(id: "text-after", text: "After")
            ],
            timestamp: "2026-08-09T00:00:00.000Z"
        )

        let message = PiChatMessage(message: source, isStreaming: true)

        XCTAssertEqual(message.id, source.id)
        XCTAssertEqual(message.parts, source.parts)
        XCTAssertTrue(message.isStreaming)
    }

    func testTranscriptProjectionPreservesTimestampForMessageMetadata() throws {
        let source = SessionTranscriptMessage(
            id: "assistant-one",
            role: .assistant,
            parts: [.text(id: "text-one", text: "Ready")],
            timestamp: "2026-08-09T12:34:56.000Z"
        )

        let message = PiChatMessage(message: source)
        let storedValue = Mirror(reflecting: message)
            .children
            .first { $0.label == "timestamp" }?
            .value
        let timestamp = storedValue.flatMap {
            Mirror(reflecting: $0).children.first?.value as? Date
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        XCTAssertEqual(timestamp, try XCTUnwrap(formatter.date(from: source.timestamp)))
    }

    func testHostModelProjectionUsesItsDisplayName() {
        let source = AgentHostModel(
            provider: "openai",
            id: "gpt-test",
            name: "GPT Test",
            contextWindow: 128_000,
            maxTokens: 16_384,
            reasoning: true,
            supportsImages: true
        )

        let model = PiModelOption(model: source)

        XCTAssertEqual(model.id, "openai/gpt-test")
        XCTAssertEqual(model.displayName, "GPT Test")
    }

    func testHostModelProjectionPreservesFastModeCapability() {
        let source = AgentHostModel(
            provider: "openai-codex",
            id: "gpt-5.6-sol",
            name: "GPT-5.6 Sol",
            contextWindow: 272_000,
            maxTokens: 128_000,
            reasoning: true,
            supportsImages: true,
            supportsFastMode: true
        )

        let model = PiModelOption(model: source)
        let capability = Mirror(reflecting: model)
            .children
            .first { $0.label == "supportsFastMode" }?
            .value as? Bool

        XCTAssertEqual(capability, true)
    }

    func testModelSearchMatchesDisplayNameProviderAndIdentifier() {
        let models = [
            PiModelOption(model: makeHostModel(provider: "anthropic", id: "claude-opus-5", name: "Claude Opus 5")),
            PiModelOption(model: makeHostModel(provider: "openai", id: "gpt-5.6-sol", name: "GPT-5.6 Sol")),
            PiModelOption(model: makeHostModel(provider: "google", id: "gemini-3.1-pro", name: "Gemini 3.1 Pro"))
        ]

        XCTAssertEqual(
            SessionComposerState.filteredModels(models, query: "opus").map(\.id),
            ["anthropic/claude-opus-5"]
        )
        XCTAssertEqual(
            SessionComposerState.filteredModels(models, query: "OPENAI").map(\.id),
            ["openai/gpt-5.6-sol"]
        )
        XCTAssertEqual(
            SessionComposerState.filteredModels(models, query: "3.1-pro").map(\.id),
            ["google/gemini-3.1-pro"]
        )
    }

    func testBranchSearchIsCaseInsensitiveAndCapsVisibleRowsAtFive() {
        let branches = [
            "main",
            "feature/session-picker",
            "feature/sidebar",
            "release/1.0",
            "fix/composer",
            "chore/tests"
        ]

        XCTAssertEqual(
            SessionComposerState.filteredGitBranches(branches, query: "FEATURE"),
            ["feature/session-picker", "feature/sidebar"]
        )
        XCTAssertEqual(
            SessionComposerState.visibleGitBranchRowCount(resultCount: branches.count),
            5
        )
        XCTAssertEqual(
            SessionComposerState.visibleGitBranchRowCount(resultCount: 3),
            3
        )
    }

    func testSlashSearchAppearsOnlyAtTheStartOfAWorkDraft() {
        XCTAssertEqual(
            SessionComposerState.slashQuery(in: "/ego", mode: .work),
            "ego"
        )
        XCTAssertEqual(
            SessionComposerState.slashQuery(in: "/ego 看一下 x.com", mode: .work),
            "ego"
        )
        XCTAssertNil(SessionComposerState.slashQuery(in: "请用 /ego", mode: .work))
        XCTAssertNil(SessionComposerState.slashQuery(in: "/ego", mode: .chat))
    }

    func testSlashSearchMatchesCommandNameDescriptionAndKind() {
        let commands = [
            AgentHostSlashCommand(
                name: "skill:ego-browser",
                description: "Browse and interact with websites",
                source: .skill
            ),
            AgentHostSlashCommand(
                name: "review",
                description: "Inspect the current changes",
                source: .extensionCommand
            )
        ]

        XCTAssertEqual(
            SessionComposerState.filteredSlashCommands(commands, query: "ego").map(\.name),
            ["skill:ego-browser"]
        )
        XCTAssertEqual(
            SessionComposerState.filteredSlashCommands(commands, query: "inspect").map(\.name),
            ["review"]
        )
        XCTAssertEqual(
            SessionComposerState.filteredSlashCommands(commands, query: "skill").map(\.name),
            ["skill:ego-browser"]
        )
    }

    func testSelectingSlashCommandPreservesTheMessageAndBuildsAnInvokablePrompt() {
        let skill = AgentHostSlashCommand(
            name: "skill:ego-browser",
            description: "Browse and interact with websites",
            source: .skill
        )

        let remainingDraft = SessionComposerState.draftAfterSelectingSlashCommand(
            from: "/ego 看一下 x.com"
        )

        XCTAssertEqual(skill.displayName, "Ego Browser")
        XCTAssertEqual(remainingDraft, "看一下 x.com")
        XCTAssertEqual(
            SessionComposerState.submissionText(
                draft: remainingDraft,
                selectedCommand: skill
            ),
            "/skill:ego-browser 看一下 x.com"
        )
        XCTAssertEqual(
            SessionComposerState.submissionText(draft: "", selectedCommand: skill),
            "/skill:ego-browser"
        )
    }

    func testSkillAndExtensionCommandsUseDifferentIcons() {
        XCTAssertEqual(
            AgentHostSlashCommandSource.skill.composerIcon,
            "doc.text"
        )
        XCTAssertNotEqual(
            AgentHostSlashCommandSource.skill.composerIcon,
            AgentHostSlashCommandSource.extensionCommand.composerIcon
        )
    }

    func testSelectedSlashCommandOnlyMovesFirstEditorLinePastItsToken() {
        let font = NSFont.systemFont(ofSize: 15)
        let textStorage = NSTextStorage(
            string: "first\nsecond\nthird",
            attributes: [.font: font]
        )
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: NSSize(width: 320, height: 120))
        textContainer.lineFragmentPadding = 0
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let lineHeight = layoutManager.defaultLineHeight(for: font)
        textContainer.exclusionPaths = [
            NSBezierPath(
                rect: SessionComposerState.slashTokenExclusionRect(
                    tokenWidth: 120,
                    lineHeight: lineHeight
                )
            )
        ]
        layoutManager.ensureLayout(for: textContainer)

        var lineOrigins: [CGFloat] = []
        layoutManager.enumerateLineFragments(
            forGlyphRange: NSRange(location: 0, length: layoutManager.numberOfGlyphs)
        ) { _, usedRect, _, _, _ in
            lineOrigins.append(usedRect.minX)
        }

        XCTAssertEqual(lineOrigins.count, 3)
        XCTAssertGreaterThan(lineOrigins[0], 120)
        XCTAssertEqual(lineOrigins[1], 0, accuracy: 0.5)
        XCTAssertEqual(lineOrigins[2], 0, accuracy: 0.5)
    }

    func testPromptHistoryWalksBackwardThenRestoresTheUnsentDraft() {
        var navigation = SessionComposerPromptHistoryNavigation()
        let prompts = ["first prompt", "second prompt", "third prompt"]

        XCTAssertEqual(
            navigation.previous(in: prompts, currentDraft: "unfinished draft"),
            "third prompt"
        )
        XCTAssertEqual(
            navigation.previous(in: prompts, currentDraft: "third prompt"),
            "second prompt"
        )
        XCTAssertEqual(
            navigation.previous(in: prompts, currentDraft: "second prompt"),
            "first prompt"
        )
        XCTAssertEqual(
            navigation.previous(in: prompts, currentDraft: "first prompt"),
            "first prompt"
        )
        XCTAssertEqual(navigation.next(in: prompts), "second prompt")
        XCTAssertEqual(navigation.next(in: prompts), "third prompt")
        XCTAssertEqual(navigation.next(in: prompts), "unfinished draft")
        XCTAssertNil(navigation.next(in: prompts))
    }

    func testPromptHistoryArrowKeysOnlyActivateAtLogicalEditorEdges() {
        let text = "first line\nsecond line"

        XCTAssertTrue(
            SessionComposerState.shouldNavigatePromptHistory(
                .previous,
                in: text,
                selection: NSRange(location: 5, length: 0)
            )
        )
        XCTAssertFalse(
            SessionComposerState.shouldNavigatePromptHistory(
                .previous,
                in: text,
                selection: NSRange(location: 11, length: 0)
            )
        )
        XCTAssertFalse(
            SessionComposerState.shouldNavigatePromptHistory(
                .next,
                in: text,
                selection: NSRange(location: 5, length: 0)
            )
        )
        XCTAssertTrue(
            SessionComposerState.shouldNavigatePromptHistory(
                .next,
                in: text,
                selection: NSRange(location: 11, length: 0)
            )
        )
        XCTAssertFalse(
            SessionComposerState.shouldNavigatePromptHistory(
                .next,
                in: text,
                selection: NSRange(location: 11, length: 2)
            )
        )
        XCTAssertFalse(
            SessionComposerState.shouldNavigatePromptHistory(
                .previous,
                in: text,
                selection: NSRange(location: 5, length: 0),
                hasMarkedText: true
            )
        )
    }

    func testPromptHistoryRestoresAnInvokableSlashCommandAsASelectedToken() {
        let command = AgentHostSlashCommand(
            name: "skill:ego-browser",
            description: "Browse websites",
            source: .skill
        )

        let recalled = SessionComposerState.recalledPrompt(
            "/skill:ego-browser 看一下 x.com",
            commands: [command]
        )

        XCTAssertEqual(recalled.selectedCommand, command)
        XCTAssertEqual(recalled.draft, "看一下 x.com")
        XCTAssertEqual(
            SessionComposerState.recalledPrompt("普通问题", commands: [command]),
            SessionComposerRecalledPrompt(draft: "普通问题", selectedCommand: nil)
        )
    }

    func testComposerWiresArrowKeysToSessionPromptHistory() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "PiWork/Features/Chat/Views/ChatView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("promptHistoryNavigation.previous"))
        XCTAssertTrue(source.contains("promptHistoryNavigation.next"))
        XCTAssertTrue(source.contains("shouldNavigatePromptHistory"))
        XCTAssertTrue(source.contains(".recallPreviousPrompt"))
        XCTAssertTrue(source.contains(".recallNextPrompt"))
    }

    func testWorkComposerWiresSlashMenuKeyboardNavigationAndSelectedToken() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "PiWork/Features/Chat/Views/ChatView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("slashCommandPanel"))
        XCTAssertTrue(source.contains("slash-command-menu"))
        XCTAssertTrue(source.contains("selectedSlashCommandToken"))
        XCTAssertTrue(source.contains("handleEditorCommand"))
        XCTAssertTrue(source.contains("command.source.composerIcon"))
        XCTAssertTrue(source.contains("await sessionStore.slashCommands"))
    }

    func testModelPickerShowsAtMostFiveRowsBeforeScrolling() {
        XCTAssertEqual(SessionComposerState.visibleModelRowCount(resultCount: 3), 3)
        XCTAssertEqual(SessionComposerState.visibleModelRowCount(resultCount: 5), 5)
        XCTAssertEqual(SessionComposerState.visibleModelRowCount(resultCount: 12), 5)
    }

    func testContextUsagePresentationMatchesCompactHoverDetails() {
        let presentation = ContextUsagePresentation(
            usage: AgentHostContextUsage(
                tokens: 194_000,
                contextWindow: 258_000,
                percent: 75.2
            )
        )

        XCTAssertEqual(presentation.progress, 0.752, accuracy: 0.001)
        XCTAssertEqual(presentation.percentText, L10n.format("context.percent_used", 75))
        XCTAssertEqual(
            presentation.detailText,
            L10n.format("context.used_total", "194k", "258k")
        )
    }

    func testContextUsagePresentationHandlesPostCompactionUnknownState() {
        let presentation = ContextUsagePresentation(
            usage: AgentHostContextUsage(
                tokens: nil,
                contextWindow: 128_000,
                percent: nil
            )
        )

        XCTAssertEqual(presentation.progress, 0)
        XCTAssertEqual(presentation.percentText, L10n.string("context.recalculating"))
        XCTAssertEqual(presentation.detailText, L10n.format("context.total", "128k"))
    }

    func testModelProvidersUseLobeHubIconAssetsAndThinkingLevelsExposeTitles() {
        let anthropic = PiModelOption(
            model: makeHostModel(provider: "anthropic", id: "claude-opus-5", name: "Claude Opus 5")
        )
        let openAI = PiModelOption(
            model: makeHostModel(provider: "openai", id: "gpt-5.6-sol", name: "GPT-5.6 Sol")
        )
        let routedClaude = PiModelOption(
            model: makeHostModel(provider: "openai", id: "claude-opus-5", name: "Claude Opus 5")
        )
        let gemini = PiModelOption(
            model: makeHostModel(provider: "google", id: "gemini-3.1-pro", name: "Gemini 3.1 Pro")
        )
        let kimi = PiModelOption(
            model: makeHostModel(provider: "moonshot", id: "kimi-k2.5", name: "Kimi K2.5")
        )
        let grok = PiModelOption(
            model: makeHostModel(provider: "xai", id: "grok-4", name: "Grok 4")
        )
        let deepSeek = PiModelOption(
            model: makeHostModel(provider: "deepseek", id: "deepseek-v3", name: "DeepSeek V3")
        )
        let unknown = PiModelOption(
            model: makeHostModel(provider: "custom", id: "private-model", name: "Private Model")
        )

        XCTAssertEqual(anthropic.providerIconAssetName, "ModelIconClaude")
        XCTAssertEqual(openAI.providerIconAssetName, "ModelIconOpenAI")
        XCTAssertEqual(routedClaude.providerIconAssetName, "ModelIconClaude")
        XCTAssertEqual(gemini.providerIconAssetName, "ModelIconGemini")
        XCTAssertEqual(kimi.providerIconAssetName, "ModelIconKimi")
        XCTAssertEqual(grok.providerIconAssetName, "ModelIconGrok")
        XCTAssertEqual(deepSeek.providerIconAssetName, "ModelIconDeepSeek")
        XCTAssertEqual(unknown.providerIconAssetName, "ModelIconLobeHub")
        XCTAssertEqual(
            AgentHostThinkingLevel.xhigh.composerTitle,
            L10n.string("settings.thinking.xhigh")
        )
        XCTAssertEqual(
            AgentHostThinkingLevel.max.composerTitle,
            L10n.string("settings.thinking.max")
        )
    }

    func testCatalogModelFamiliesUseOfficialBrandAssets() {
        let expectations = [
            ("openrouter", "qwen/qwen3-coder", "Qwen3 Coder", "ModelIconQwen"),
            ("amazon-bedrock", "meta.llama4-maverick", "Llama 4 Maverick", "ModelIconMeta"),
            ("openrouter", "mistralai/devstral-small", "Devstral Small", "ModelIconMistral"),
            ("vercel-ai-gateway", "minimax/minimax-m2", "MiniMax M2", "ModelIconMiniMax"),
            ("openrouter", "z-ai/glm-5", "GLM 5", "ModelIconZAI"),
            ("openrouter", "xiaomi/mimo-v2-flash", "MiMo V2 Flash", "ModelIconXiaomiMiMo"),
            ("openrouter", "nvidia/nemotron-3-nano", "Nemotron 3 Nano", "ModelIconNVIDIA"),
            ("amazon-bedrock", "amazon.nova-pro", "Amazon Nova Pro", "ModelIconNova"),
            ("google", "gemma-3-27b", "Gemma 3 27B", "ModelIconGemma"),
            ("cohere", "command-r-plus", "Command R+", "ModelIconCohere"),
            ("openrouter", "stepfun/step-3.5-flash", "Step 3.5 Flash", "ModelIconStepFun"),
            ("azure", "phi-4", "Phi 4", "ModelIconMicrosoft"),
            ("cloudflare-ai-gateway", "o3-mini", "o3-mini", "ModelIconOpenAI")
        ]

        for (provider, id, name, assetName) in expectations {
            let model = PiModelOption(
                model: makeHostModel(provider: provider, id: id, name: name)
            )
            XCTAssertEqual(model.providerIconAssetName, assetName, "Unexpected icon for \(name)")
        }
    }

    func testThinkingSliderMapsItsPositionToAvailableModelLevels() {
        let levels: [AgentHostThinkingLevel] = [.off, .minimal, .low, .medium, .high]

        XCTAssertEqual(
            SessionComposerState.thinkingLevel(forSliderValue: 0, availableLevels: levels),
            .off
        )
        XCTAssertEqual(
            SessionComposerState.thinkingLevel(forSliderValue: 2.2, availableLevels: levels),
            .low
        )
        XCTAssertEqual(
            SessionComposerState.thinkingLevel(forSliderValue: 99, availableLevels: levels),
            .high
        )
        XCTAssertNil(
            SessionComposerState.thinkingLevel(forSliderValue: 0, availableLevels: [])
        )
    }

    func testEmptyPersistedMessageIsHiddenUnlessItIsStreaming() {
        let source = AgentHostSessionMessage(
            id: "empty-assistant",
            role: .assistant,
            content: [],
            timestamp: "2026-08-09T00:00:00.000Z",
            provider: nil,
            model: nil,
            stopReason: nil,
            errorMessage: nil,
            toolCallId: nil,
            toolName: nil,
            isError: nil
        )

        XCTAssertFalse(PiChatMessage(message: source).isVisible)
        XCTAssertTrue(PiChatMessage(message: source, isStreaming: true).isVisible)
    }

    func testPrimaryActionReflectsDraftAndExecutionState() {
        XCTAssertEqual(SessionComposerState.primaryAction(draft: "", isExecuting: false), .none)
        XCTAssertEqual(SessionComposerState.primaryAction(draft: "  \n", isExecuting: false), .none)
        XCTAssertEqual(SessionComposerState.primaryAction(draft: "整理项目", isExecuting: false), .send)
        XCTAssertEqual(SessionComposerState.primaryAction(draft: "", isExecuting: true), .stop)
        XCTAssertEqual(SessionComposerState.primaryAction(draft: "后续消息", isExecuting: true), .stop)
    }

    func testOnlyWorkSessionsExposeProjectSelection() {
        XCTAssertFalse(SidebarTab.chat.showsProjectSelection)
        XCTAssertTrue(SidebarTab.work.showsProjectSelection)
    }

    func testWorkAccessModesHaveExplicitUserFacingMeaning() {
        XCTAssertEqual(AgentHostAccessMode.readOnly.composerTitle, L10n.string("access.read_only.title"))
        XCTAssertEqual(AgentHostAccessMode.ask.composerTitle, L10n.string("access.ask.title"))
        XCTAssertEqual(AgentHostAccessMode.full.composerTitle, L10n.string("access.full.title"))
        XCTAssertEqual(
            AgentHostAccessMode.full.composerDescription,
            L10n.string("access.full.description")
        )
    }

    func testConversationSurfaceExposesAccessAndApprovalControls() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PiWork/Features/Chat/Views/ChatView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("session-access-mode"))
        XCTAssertTrue(source.contains("InlineApprovalActions"))
        XCTAssertTrue(source.contains("allow-approval-once"))
        XCTAssertTrue(source.contains("deny-approval"))
    }

    func testConversationUsesHalfHeightTopControlClearance() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PiWork/Features/Chat/Views/ChatView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("Color.clear.frame(height: 32)"))
        XCTAssertFalse(source.contains("Color.clear.frame(height: 64)"))
    }

    func testSuggestionCardsUseCompactLandscapeHeight() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PiWork/Features/Chat/Views/ChatView.swift"),
            encoding: .utf8
        )
        let cardStart = try XCTUnwrap(source.range(of: "private struct SessionSuggestionCard"))
        let cardEnd = try XCTUnwrap(
            source.range(of: "private struct GitBranchIcon", range: cardStart.upperBound..<source.endIndex)
        )
        let cardSource = source[cardStart.lowerBound..<cardEnd.lowerBound]

        XCTAssertTrue(cardSource.contains("Spacer(minLength: 0)"))
        XCTAssertTrue(cardSource.contains(".frame(height: 104)"))
        XCTAssertTrue(cardSource.contains(
            ".frame(maxWidth: .infinity, alignment: .leading)"
        ))
        XCTAssertFalse(cardSource.contains("minHeight: 112"))
    }

    func testExploreSuggestionUsesResolvableSystemIcon() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PiWork/Features/Chat/Views/ChatView.swift"),
            encoding: .utf8
        )
        let defaultsStart = try XCTUnwrap(source.range(of: "static var defaults"))
        let defaultsSource = String(source[defaultsStart.lowerBound...])
        let iconPattern = #"SessionSuggestion\(\s*icon: \"([^\"]+)\""#
        let iconRegex = try NSRegularExpression(pattern: iconPattern)
        let searchRange = NSRange(defaultsSource.startIndex..., in: defaultsSource)
        let match = try XCTUnwrap(iconRegex.firstMatch(in: defaultsSource, range: searchRange))
        let iconRange = try XCTUnwrap(Range(match.range(at: 1), in: defaultsSource))
        let iconName = String(defaultsSource[iconRange])

        XCTAssertNotNil(
            NSImage(systemSymbolName: iconName, accessibilityDescription: nil),
            "The explore suggestion icon '\(iconName)' must resolve on macOS"
        )
    }

    func testTranscriptSoftensTopScrollBoundaryWithGradientMaterial() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PiWork/Features/Chat/Views/ChatView.swift"),
            encoding: .utf8
        )
        let transcriptStart = try XCTUnwrap(source.range(of: "private var transcript"))
        let transcriptEnd = try XCTUnwrap(
            source.range(of: "private var emptySession", range: transcriptStart.upperBound..<source.endIndex)
        )
        let transcriptSource = source[transcriptStart.lowerBound..<transcriptEnd.lowerBound]

        XCTAssertTrue(transcriptSource.contains(".overlay(alignment: .top)"))
        XCTAssertTrue(transcriptSource.contains(".fill(.ultraThinMaterial)"))
        XCTAssertTrue(transcriptSource.contains("LinearGradient("))
        XCTAssertTrue(transcriptSource.contains(".frame(height: 16)"))
        XCTAssertTrue(transcriptSource.contains(".opacity(0.32)"))
        XCTAssertFalse(transcriptSource.contains(".frame(height: 24)"))
        XCTAssertTrue(transcriptSource.contains(".allowsHitTesting(false)"))
    }

    func testAccessModeMenuHasVisibleAnimatedHoverFeedback() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PiWork/Features/Chat/Views/ChatView.swift"),
            encoding: .utf8
        )
        let menuStart = try XCTUnwrap(source.range(of: "private func accessModeMenu"))
        let menuEnd = try XCTUnwrap(
            source.range(of: "@ViewBuilder", range: menuStart.upperBound..<source.endIndex)
        )
        let menuSource = source[menuStart.lowerBound..<menuEnd.lowerBound]

        XCTAssertTrue(menuSource.contains(
            ".fill(Color.primary.opacity(isAccessMenuHovering ? 0.08 : 0))"
        ))
        XCTAssertTrue(menuSource.contains(
            ".stroke(Color.primary.opacity(isAccessMenuHovering ? 0.10 : 0), lineWidth: 1)"
        ))
        XCTAssertTrue(menuSource.contains(
            ".animation(.easeOut(duration: 0.12), value: isAccessMenuHovering)"
        ))
    }

    func testAssistantMarkdownOverridesGitHubOpaqueTextBackground() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PiWork/Features/Chat/Views/ChatView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("private let assistantMarkdownTheme = Theme.gitHub"))
        XCTAssertTrue(source.contains(".markdownTheme(assistantMarkdownTheme)"))
        XCTAssertFalse(source.contains(".markdownTheme(.gitHub)"))
    }

    func testAssistantRepliesRenderAsFlatCopyableTimeline() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PiWork/Features/Chat/Views/ChatView.swift"),
            encoding: .utf8
        )

        let timelineStart = try XCTUnwrap(source.range(of: "private var assistantTimeline"))
        let timelineEnd = try XCTUnwrap(
            source.range(
                of: "private var copyMessageLabel",
                range: timelineStart.upperBound..<source.endIndex
            )
        )
        let timelineSource = source[timelineStart.lowerBound..<timelineEnd.lowerBound]

        XCTAssertTrue(timelineSource.contains("Text(timestamp, style: .time)"))
        XCTAssertTrue(timelineSource.contains("Button(action: copyMessage)"))
        XCTAssertFalse(timelineSource.contains(".background(AppPalette.translucentSurface"))
        XCTAssertFalse(timelineSource.contains(".adaptiveCornerRadius(18)"))
        XCTAssertTrue(source.contains("MessageClipboard.copy(message.copyableText)"))
        XCTAssertTrue(source.contains("L10n.string(\"chat.message.copy\")"))
    }

    func testMessageClipboardCopiesTheExactResponseText() {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("pi-work-copy-test-\(UUID().uuidString)")
        )

        XCTAssertTrue(MessageClipboard.copy("第一行\n第二行", to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "第一行\n第二行")
    }

    func testMessageCopyFeedbackUsesACheckmarkForThreeSeconds() {
        XCTAssertEqual(MessageCopyFeedback.iconName(isCopied: false), "doc.on.doc")
        XCTAssertEqual(MessageCopyFeedback.iconName(isCopied: true), "checkmark")
        XCTAssertEqual(MessageCopyFeedback.resetDelayNanoseconds, 3_000_000_000)
    }

    func testAssistantCopyButtonWiresSuccessfulCopyFeedback() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "PiWork/Features/Chat/Views/ChatView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("@State private var isMessageCopied = false"))
        XCTAssertTrue(source.contains("MessageCopyFeedback.iconName"))
        XCTAssertTrue(source.contains("copyFeedbackResetTask"))
        XCTAssertTrue(source.contains("L10n.string(\"chat.message.copied\")"))
    }

    func testAssistantTimelinePlacesCopyBeforeTimestampAtLeadingEdge() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PiWork/Features/Chat/Views/ChatView.swift"),
            encoding: .utf8
        )
        let timelineStart = try XCTUnwrap(source.range(of: "private var assistantTimeline"))
        let timelineEnd = try XCTUnwrap(
            source.range(
                of: "private var copyMessageLabel",
                range: timelineStart.upperBound..<source.endIndex
            )
        )
        let timelineSource = source[timelineStart.lowerBound..<timelineEnd.lowerBound]
        let footerStart = try XCTUnwrap(timelineSource.range(of: "HStack(spacing: 8)"))
        let footerSource = timelineSource[footerStart.lowerBound...]
        let copyStart = try XCTUnwrap(
            footerSource.range(of: "Button(action: copyMessage)")
        )
        let timestampStart = try XCTUnwrap(footerSource.range(of: "if let timestamp"))
        let trailingSpacer = try XCTUnwrap(footerSource.range(of: "Spacer(minLength: 8)"))

        XCTAssertLessThan(copyStart.lowerBound, timestampStart.lowerBound)
        XCTAssertLessThan(timestampStart.lowerBound, trailingSpacer.lowerBound)
    }

    func testConversationSurfaceExposesSearchableModelAndThinkingControls() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PiWork/Features/Chat/Views/ChatView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("model-picker-search"))
        XCTAssertTrue(source.contains("model-picker-scroll-view"))
        XCTAssertTrue(source.contains("session-thinking-level"))
        XCTAssertTrue(source.contains("availableThinkingLevels"))
    }

    func testSharedChatAndWorkComposerOmitsVoiceInputButton() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PiWork/Features/Chat/Views/ChatView.swift"),
            encoding: .utf8
        )
        let editorStart = try XCTUnwrap(source.range(of: "private var editor: some View"))
        let editorEnd = try XCTUnwrap(
            source.range(
                of: "private var selectedSlashCommandTokenWidth",
                range: editorStart.upperBound..<source.endIndex
            )
        )
        let editorSource = source[editorStart.lowerBound..<editorEnd.lowerBound]

        XCTAssertFalse(editorSource.contains("Image(systemName: \"mic\")"))
    }

    func testModelPickerUsesOfficialIconsAndCompactWidth() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PiWork/Features/Chat/Views/ChatView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("Image(model.providerIconAssetName)"))
        XCTAssertTrue(source.contains(".renderingMode(.template)"))
        XCTAssertTrue(source.contains(".foregroundStyle(Color.primary)"))
        XCTAssertTrue(source.contains(".frame(width: 272)"))
        XCTAssertFalse(source.contains(".frame(width: 330)"))
        XCTAssertFalse(source.contains("Image(systemName: model.providerIconName)"))
    }

    func testComposerModelPickerOmitsCurrentModelIcon() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PiWork/Features/Chat/Views/ChatView.swift"),
            encoding: .utf8
        )
        let pickerStart = try XCTUnwrap(source.range(of: "private var modelPicker"))
        let contentStart = try XCTUnwrap(
            source.range(of: "private var modelPickerContent", range: pickerStart.upperBound..<source.endIndex)
        )
        let pickerSource = source[pickerStart.lowerBound..<contentStart.lowerBound]

        XCTAssertFalse(pickerSource.contains("ModelProviderIcon"))
        XCTAssertFalse(pickerSource.contains("Image(systemName: \"bolt.fill\")"))
    }

    func testModelSelectionHighlightExcludesFastModeControl() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PiWork/Features/Chat/Views/ChatView.swift"),
            encoding: .utf8
        )
        let rowStart = try XCTUnwrap(source.range(of: "private func modelPickerRow"))
        let fastButtonStart = try XCTUnwrap(
            source.range(of: "private func fastModeButton", range: rowStart.upperBound..<source.endIndex)
        )
        let rowSource = source[rowStart.lowerBound..<fastButtonStart.lowerBound]

        XCTAssertTrue(rowSource.contains("isSelected: model == selectedModel"))
        XCTAssertFalse(rowSource.contains(".background("))
        XCTAssertTrue(rowSource.contains("fastModeButton(for: model)"))
    }

    func testFastModeControlUsesSlidingCapsule() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PiWork/Features/Chat/Views/ChatView.swift"),
            encoding: .utf8
        )
        let fastButtonStart = try XCTUnwrap(source.range(of: "private func fastModeButton"))
        let filteredModelsStart = try XCTUnwrap(
            source.range(of: "private var filteredModels", range: fastButtonStart.upperBound..<source.endIndex)
        )
        let fastButtonSource = source[fastButtonStart.lowerBound..<filteredModelsStart.lowerBound]
        let switchStart = try XCTUnwrap(source.range(of: "private struct FastModeCapsuleSwitch"))
        let providerIconStart = try XCTUnwrap(
            source.range(of: "private struct ModelProviderIcon", range: switchStart.upperBound..<source.endIndex)
        )
        let switchSource = source[switchStart.lowerBound..<providerIconStart.lowerBound]

        XCTAssertTrue(fastButtonSource.contains("FastModeCapsuleSwitch("))
        XCTAssertTrue(fastButtonSource.contains(".buttonStyle(.plain)"))
        XCTAssertFalse(fastButtonSource.contains("isModelPickerPresented = false"))
        XCTAssertTrue(switchSource.contains("Capsule()"))
        XCTAssertTrue(switchSource.contains("Circle()"))
        XCTAssertTrue(switchSource.contains(".offset(x: isOn ? 7 : -7)"))
        XCTAssertTrue(switchSource.contains("value: isOn"))
    }

    func testLobeHubModelIconAssetsArePresent() {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let assetCatalog = repositoryRoot.appendingPathComponent(
            "PiWork/Resources/Assets.xcassets"
        )
        let assetNames = [
            "ModelIconClaude",
            "ModelIconCohere",
            "ModelIconDeepSeek",
            "ModelIconGemini",
            "ModelIconGemma",
            "ModelIconGrok",
            "ModelIconKimi",
            "ModelIconLobeHub",
            "ModelIconMeta",
            "ModelIconMicrosoft",
            "ModelIconMiniMax",
            "ModelIconMistral",
            "ModelIconNova",
            "ModelIconNVIDIA",
            "ModelIconOpenAI",
            "ModelIconQwen",
            "ModelIconStepFun",
            "ModelIconXiaomiMiMo",
            "ModelIconZAI"
        ]

        for assetName in assetNames {
            let manifest = assetCatalog
                .appendingPathComponent("\(assetName).imageset")
                .appendingPathComponent("Contents.json")
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: manifest.path),
                "Missing LobeHub icon asset: \(assetName)"
            )
            let manifestContents = try? String(contentsOf: manifest, encoding: .utf8)
            XCTAssertTrue(
                manifestContents?.contains("\"template-rendering-intent\" : \"template\"") == true,
                "LobeHub icon must adapt to light and dark appearance: \(assetName)"
            )
        }
    }

    func testGeminiUsesRasterAssetToAvoidCoreSVGRenderingRegression() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifest = repositoryRoot
            .appendingPathComponent("PiWork/Resources/Assets.xcassets/ModelIconGemini.imageset")
            .appendingPathComponent("Contents.json")
        let manifestContents = try String(contentsOf: manifest, encoding: .utf8)

        XCTAssertTrue(manifestContents.contains("\"filename\" : \"gemini.png\""))
        XCTAssertFalse(manifestContents.contains(".svg"))
    }

    func testThinkingPickerRequestsUpwardPopoverPlacement() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PiWork/Features/Chat/Views/ChatView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            source.contains(
                ".popover(isPresented: $isThinkingPickerPresented, arrowEdge: .bottom)"
            )
        )
    }

    func testThinkingPickerUsesHorizontalEffortSlider() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PiWork/Features/Chat/Views/ChatView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("Slider("))
        XCTAssertTrue(source.contains("L10n.string(\"chat.faster\")"))
        XCTAssertTrue(source.contains("L10n.string(\"chat.smarter\")"))
    }

    func testEveryModelRowShowsCapabilityAwareFastButton() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PiWork/Features/Chat/Views/ChatView.swift"),
            encoding: .utf8
        )
        let editorStart = try XCTUnwrap(source.range(of: "private var editor"))
        let pickerStart = try XCTUnwrap(
            source.range(of: "private var modelPicker", range: editorStart.upperBound..<source.endIndex)
        )
        let rowStart = try XCTUnwrap(source.range(of: "private func modelPickerRow"))
        let rowEnd = try XCTUnwrap(
            source.range(of: "private var filteredModels", range: rowStart.upperBound..<source.endIndex)
        )
        let editorSource = source[editorStart.lowerBound..<pickerStart.lowerBound]
        let rowSource = source[rowStart.lowerBound..<rowEnd.lowerBound]

        XCTAssertFalse(editorSource.contains("fastModeToggle"))
        XCTAssertFalse(rowSource.contains("if model == selectedModel"))
        XCTAssertTrue(rowSource.contains("fastModeButton(for: model)"))
        XCTAssertTrue(source.contains("FastModeCapsuleSwitch("))
        XCTAssertTrue(source.contains(".disabled(!model.supportsFastMode)"))
        XCTAssertTrue(source.contains("model == selectedModel && modelOptions.fastMode.enabled"))
        XCTAssertTrue(source.contains("onToggleFastMode(model)"))
    }

    func testThinkingPickerKeepsOnlyOneMillionContextSwitch() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PiWork/Features/Chat/Views/ChatView.swift"),
            encoding: .utf8
        )
        let pickerStart = try XCTUnwrap(
            source.range(of: "private func thinkingLevelPickerContent")
        )
        let pickerEnd = try XCTUnwrap(
            source.range(of: "private func modelOptionToggle", range: pickerStart.upperBound..<source.endIndex)
        )
        let pickerSource = source[pickerStart.lowerBound..<pickerEnd.lowerBound]

        XCTAssertTrue(pickerSource.contains("L10n.string(\"chat.one_million_context\")"))
        XCTAssertTrue(pickerSource.contains("one-million-context-toggle"))
        XCTAssertFalse(pickerSource.contains("Text(\"Fast 模式\")"))
        XCTAssertFalse(pickerSource.contains("option: .fastMode"))
    }

    func testComposerExposesContextUsageIndicatorAndHoverDetails() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PiWork/Features/Chat/Views/ChatView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("ContextUsageIndicator"))
        XCTAssertTrue(source.contains("context-usage-indicator"))
        XCTAssertTrue(source.contains(".popover(isPresented: $isContextUsagePresented"))
    }

    func testConversationSurfaceUsesSharedSessionStoreForChatAndWork() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PiWork/Features/Chat/Views/ChatView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("selectedWorkSessionIdByProjectPath"))
        XCTAssertFalse(source.contains("@StateObject private var viewModel"))
    }

    func testProjectPickerOpensAboveComposer() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PiWork/Features/Chat/Views/ChatView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("isPresented: $isProjectPickerPresented"))
        XCTAssertTrue(source.contains("SessionComposerState.projectPickerPopoverAnchorX("))
        XCTAssertTrue(source.contains("arrowEdge: .top"))
        XCTAssertTrue(
            source.contains(
                ".frame(width: SessionComposerState.projectPickerPopoverWidth)"
            )
        )
    }

    func testProjectPickerPopoverAlignsWithComposerLeadingEdge() {
        let composerWidth: CGFloat = 640
        let popoverWidth = SessionComposerState.projectPickerPopoverWidth
        let anchorX = SessionComposerState.projectPickerPopoverAnchorX(
            composerWidth: composerWidth
        )

        XCTAssertEqual(
            anchorX * composerWidth - popoverWidth / 2,
            0,
            accuracy: 0.001
        )
    }

    func testProjectBarOmitsRedundantLocalIndicator() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PiWork/Features/Chat/Views/ChatView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("Label(\"本地\", systemImage: \"laptopcomputer\")"))
    }

    func testProjectBarUsesSearchableCreationOnlyGitBranchPicker() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("PiWork/Features/Chat/Views/ChatView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("GitBranchIcon"))
        XCTAssertTrue(source.contains("branch-picker-search"))
        XCTAssertTrue(source.contains("branch-picker-scroll-view"))
        XCTAssertTrue(source.contains("canSelectGitBranch"))
        XCTAssertTrue(source.contains("await sessionStore.gitBranches"))
        XCTAssertTrue(source.contains("await sessionStore.setGitBranch"))
        XCTAssertFalse(source.contains("private enum ProjectMetadata"))
        XCTAssertFalse(source.contains("appendingPathComponent(\"HEAD\")"))
    }

    func testEditorHeightClampsBetweenTwoAndFourLines() {
        XCTAssertEqual(SessionComposerState.editorHeight(for: 0), 44)
        XCTAssertEqual(SessionComposerState.editorHeight(for: 62), 62)
        XCTAssertEqual(SessionComposerState.editorHeight(for: 120), 80)
        XCTAssertFalse(SessionComposerState.editorShouldScroll(contentHeight: 80))
        XCTAssertTrue(SessionComposerState.editorShouldScroll(contentHeight: 81))
    }

    func testReturnSubmitsMessage() {
        XCTAssertEqual(
            SessionComposerState.returnKeyAction(
                isShiftPressed: false,
                hasMarkedText: false
            ),
            .submit
        )
    }

    func testShiftReturnInsertsNewline() {
        XCTAssertEqual(
            SessionComposerState.returnKeyAction(
                isShiftPressed: true,
                hasMarkedText: false
            ),
            .insertNewline
        )
    }

    func testReturnDefersToActiveInputMethod() {
        XCTAssertEqual(
            SessionComposerState.returnKeyAction(
                isShiftPressed: false,
                hasMarkedText: true
            ),
            .deferToInputMethod
        )
    }

    func testComposerBorderRemainsNeutral() {
        XCTAssertEqual(SessionComposerState.borderOpacity(isHovering: false), 0.09)
        XCTAssertEqual(SessionComposerState.borderOpacity(isHovering: true), 0.16)
        XCTAssertEqual(SessionComposerState.borderWidth, 0.5)
    }

    @MainActor
    func testHomeShowsEverySuggestionAtMinimumContentWidth() throws {
        let view = ChatView(
            mode: .work,
            projects: [],
            selectedProject: .constant(nil),
            sessionStore: makeInactiveSessionStore(),
            onAddFolder: {}
        )
        .frame(width: 646, height: 600)
        .environment(\.colorScheme, .light)

        let bitmap = try TestViewRenderer.render(view, size: CGSize(width: 646, height: 600))

        XCTAssertGreaterThan(
            bitmap.countPixels { color in
                color.redComponent > 0.75
                    && color.greenComponent > 0.25
                    && color.greenComponent < 0.75
                    && color.blueComponent < 0.35
            },
            0,
            "The orange fourth suggestion must be visible without horizontal scrolling"
        )
    }

    @MainActor
    func testComposerStartsAtCompactTwoLineHeight() throws {
        let view = ChatView(
            mode: .work,
            projects: [],
            selectedProject: .constant(nil),
            sessionStore: makeInactiveSessionStore(),
            onAddFolder: {}
        )
        .frame(width: 646, height: 600)
        .background(Color.gray)
        .environment(\.colorScheme, .light)

        let bitmap = try TestViewRenderer.render(view, size: CGSize(width: 646, height: 600))
        let editorHeight = bitmap.longestVerticalRun(atX: 323, in: 350..<590) { color in
            color.redComponent > 0.92
                && color.greenComponent > 0.92
                && color.blueComponent > 0.92
        }

        XCTAssertLessThanOrEqual(editorHeight, 120)
    }

}

private func makeHostModel(provider: String, id: String, name: String) -> AgentHostModel {
    AgentHostModel(
        provider: provider,
        id: id,
        name: name,
        contextWindow: 128_000,
        maxTokens: 16_384,
        reasoning: true,
        supportsImages: true
    )
}

@MainActor
private func makeInactiveSessionStore() -> SessionStore {
    SessionStore(
        service: AgentHostService(
            executableURL: URL(fileURLWithPath: "/usr/bin/false"),
            requiredCapabilities: []
        )
    )
}

enum TestViewRenderer {
    @MainActor
    static func render<V: View>(_ view: V, size: CGSize) throws -> NSBitmapImageRep {
        let hostingView = host(view, size: size)

        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(size.width),
                pixelsHigh: Int(size.height),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        bitmap.size = size
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        return bitmap
    }

    @MainActor
    private static func host<V: View>(_ view: V, size: CGSize) -> NSHostingView<V> {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()
        return hostingView
    }
}

private extension NSBitmapImageRep {
    func countPixels(matching predicate: (NSColor) -> Bool) -> Int {
        var count = 0
        for y in 0..<pixelsHigh {
            for x in 0..<pixelsWide {
                guard
                    let color = colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                    color.alphaComponent > 0.5,
                    predicate(color)
                else { continue }
                count += 1
            }
        }
        return count
    }

    func longestVerticalRun(
        atX x: Int,
        in rows: Range<Int>,
        matching predicate: (NSColor) -> Bool
    ) -> Int {
        var longest = 0
        var current = 0

        for y in rows {
            guard
                let color = colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                color.alphaComponent > 0.5,
                predicate(color)
            else {
                longest = max(longest, current)
                current = 0
                continue
            }
            current += 1
        }

        return max(longest, current)
    }
}
