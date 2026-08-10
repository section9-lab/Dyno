import XCTest
@testable import PiWork

final class AssistantTimelinePresentationTests: XCTestCase {
    func testAdjacentToolOnlyAssistantGenerationsShareOneMessageRow() throws {
        let first = makeTool(id: "first", state: .completed, isError: false)
        let second = makeTool(id: "second", state: .completed, isError: false)
        let messages = [
            makeAssistantMessage(id: "assistant-one", parts: [.tool(first)]),
            makeAssistantMessage(id: "assistant-two", parts: [.tool(second)])
        ]

        let grouped = AssistantTranscriptPresentation.groupAdjacentTools(in: messages)

        let message = try XCTUnwrap(grouped.first)
        XCTAssertEqual(grouped.count, 1)
        XCTAssertEqual(message.id, "assistant-one")
        XCTAssertEqual(message.parts, [.tool(first), .tool(second)])
        XCTAssertEqual(
            AssistantTranscriptPresentation.blocks(from: message.parts),
            [.tools(AssistantToolGroup(id: "tool-group:first", tools: [first, second]))]
        )
    }

    func testVisibleThinkingSeparatesToolOnlyAssistantGenerations() {
        let first = makeTool(id: "first", state: .completed, isError: false)
        let second = makeTool(id: "second", state: .completed, isError: false)
        let thinking = SessionThinkingRecord(
            id: "thinking",
            text: "Checking the result",
            state: .completed,
            redacted: false
        )
        let messages = [
            makeAssistantMessage(id: "assistant-one", parts: [.tool(first)]),
            makeAssistantMessage(id: "assistant-thinking", parts: [.thinking(thinking)]),
            makeAssistantMessage(id: "assistant-two", parts: [.tool(second)])
        ]

        let grouped = AssistantTranscriptPresentation.groupAdjacentTools(in: messages)

        XCTAssertEqual(
            grouped.map(\.id),
            ["assistant-one", "assistant-thinking", "assistant-two"]
        )
    }

    func testToolOnlyGenerationJoinsPreviousAssistantThatEndsWithATool() throws {
        let first = makeTool(id: "first", state: .completed, isError: false)
        let second = makeTool(id: "second", state: .completed, isError: false)
        let messages = [
            makeAssistantMessage(
                id: "assistant-one",
                parts: [
                    .text(id: "intro", text: "开始执行。"),
                    .tool(first)
                ]
            ),
            makeAssistantMessage(id: "assistant-two", parts: [.tool(second)])
        ]

        let grouped = AssistantTranscriptPresentation.groupAdjacentTools(in: messages)

        let message = try XCTUnwrap(grouped.first)
        XCTAssertEqual(grouped.count, 1)
        XCTAssertEqual(
            message.parts,
            [.text(id: "intro", text: "开始执行。"), .tool(first), .tool(second)]
        )
        XCTAssertEqual(
            AssistantTranscriptPresentation.blocks(from: message.parts),
            [
                .text(id: "intro", text: "开始执行。"),
                .tools(AssistantToolGroup(id: "tool-group:first", tools: [first, second]))
            ]
        )
    }

    func testConsecutiveToolsAreGroupedUntilVisibleContentSeparatesThem() {
        let first = makeTool(id: "first", state: .completed, isError: false)
        let second = makeTool(id: "second", state: .running)
        let third = makeTool(id: "third", state: .completed, isError: false)

        let blocks = AssistantTranscriptPresentation.blocks(from: [
            .text(id: "intro", text: "先检查项目。"),
            .tool(first),
            .tool(second),
            .text(id: "update", text: "接下来修改文件。"),
            .tool(third)
        ])

        XCTAssertEqual(blocks, [
            .text(id: "intro", text: "先检查项目。"),
            .tools(AssistantToolGroup(id: "tool-group:first", tools: [first, second])),
            .text(id: "update", text: "接下来修改文件。"),
            .tools(AssistantToolGroup(id: "tool-group:third", tools: [third]))
        ])
    }

    func testToolGroupIdentityStaysStableWhenStreamingAppendsAnotherTool() throws {
        let first = makeTool(id: "first", state: .running)
        let second = makeTool(id: "second", state: .running)

        let initial = AssistantTranscriptPresentation.blocks(from: [.tool(first)])
        let updated = AssistantTranscriptPresentation.blocks(from: [.tool(first), .tool(second)])

        XCTAssertEqual(try XCTUnwrap(initial.first?.id), try XCTUnwrap(updated.first?.id))
    }

    func testMessageMetadataAnchorsToTheLastTextInsteadOfATrailingToolGroup() {
        let blocks = AssistantTranscriptPresentation.blocks(from: [
            .text(id: "answer", text: "请先完成人机验证。"),
            .tool(makeTool(id: "browser", state: .completed, isError: false))
        ])

        XCTAssertEqual(
            AssistantTranscriptPresentation.metadataAnchorID(in: blocks),
            "answer"
        )
    }

    func testHiddenThinkingDoesNotSplitConsecutiveToolGroups() {
        let first = makeTool(id: "first", state: .completed, isError: false)
        let second = makeTool(id: "second", state: .completed, isError: false)
        let thinking = SessionThinkingRecord(
            id: "thinking",
            text: "",
            state: .completed,
            redacted: false
        )

        let blocks = AssistantTranscriptPresentation.blocks(from: [
            .tool(first),
            .thinking(thinking),
            .tool(second)
        ])

        XCTAssertEqual(blocks, [
            .tools(AssistantToolGroup(id: "tool-group:first", tools: [first, second]))
        ])
    }

    func testCompletedThinkingWithContentRemainsAvailableAsAnExpandableBlock() {
        let thinking = SessionThinkingRecord(
            id: "thinking",
            text: "Checked the available APIs.",
            state: .completed,
            redacted: false
        )

        XCTAssertEqual(
            AssistantTranscriptPresentation.blocks(from: [.thinking(thinking)]),
            [.thinking(thinking)]
        )
    }

    func testRunningThinkingWithoutTextDoesNotCreateATransientBlock() {
        let thinking = SessionThinkingRecord(
            id: "thinking",
            text: "",
            state: .running,
            redacted: false
        )

        XCTAssertEqual(
            AssistantTranscriptPresentation.blocks(from: [.thinking(thinking)]),
            []
        )
    }

    func testRunningThinkingRemainsVisibleBetweenToolGroups() {
        let first = makeTool(id: "first", state: .completed, isError: false)
        let second = makeTool(id: "second", state: .running)
        let thinking = SessionThinkingRecord(
            id: "thinking",
            text: "Inspecting sources",
            state: .running,
            redacted: false
        )

        let blocks = AssistantTranscriptPresentation.blocks(from: [
            .tool(first),
            .thinking(thinking),
            .tool(second)
        ])

        XCTAssertEqual(blocks, [
            .tools(AssistantToolGroup(id: "tool-group:first", tools: [first])),
            .thinking(thinking),
            .tools(AssistantToolGroup(id: "tool-group:second", tools: [second]))
        ])
    }

    func testTaggedThinkingTextBecomesAThinkingBlockBeforeTheResponseAndTool() {
        let tool = makeTool(id: "read", state: .running)
        let blocks = AssistantTranscriptPresentation.blocks(from: [
            .text(
                id: "legacy",
                text: "<think>Inspecting sources</think>\n\nStarting the tool."
            ),
            .tool(tool)
        ])

        XCTAssertEqual(blocks, [
            .thinking(
                SessionThinkingRecord(
                    id: "legacy:thinking",
                    text: "Inspecting sources",
                    state: .completed,
                    redacted: false
                )
            ),
            .text(id: "legacy:response", text: "Starting the tool."),
            .tools(AssistantToolGroup(id: "tool-group:read", tools: [tool]))
        ])
    }

    func testUnclosedTaggedThinkingTextRemainsAStreamingThinkingBlock() {
        let blocks = AssistantTranscriptPresentation.blocks(from: [
            .text(id: "legacy", text: "<think>Inspecting sources")
        ])

        XCTAssertEqual(blocks, [
            .thinking(
                SessionThinkingRecord(
                    id: "legacy:thinking",
                    text: "Inspecting sources",
                    state: .running,
                    redacted: false
                )
            )
        ])
    }

    func testRunningStatusReportsFinishedAndTotalSteps() {
        let group = AssistantToolGroup(id: "group", tools: [
            makeTool(id: "done", state: .completed, isError: false),
            makeTool(id: "active", state: .running)
        ])

        XCTAssertEqual(group.status, .running(completed: 1, total: 2))
    }

    func testApprovalStatusTakesPriorityOverRunningSteps() {
        let approval = AgentHostApprovalRequest(
            id: "approval",
            toolCallId: "waiting",
            toolName: "bash",
            summary: "bun test"
        )
        let group = AssistantToolGroup(id: "group", tools: [
            makeTool(id: "active", state: .running),
            makeTool(id: "waiting", state: .awaitingApproval, approval: approval)
        ])

        XCTAssertEqual(group.status, .approvalRequired)
    }

    func testFailedStatusCountsTerminalErrors() {
        let group = AssistantToolGroup(id: "group", tools: [
            makeTool(id: "done", state: .completed, isError: false),
            makeTool(id: "failed", state: .completed, isError: true)
        ])

        XCTAssertEqual(group.status, .failed(total: 2, failed: 1))
    }

    func testCompletedStatusRequiresEveryStepToSucceed() {
        let group = AssistantToolGroup(id: "group", tools: [
            makeTool(id: "first", state: .completed, isError: false),
            makeTool(id: "second", state: .completed, isError: false)
        ])

        XCTAssertEqual(group.status, .completed(total: 2))
    }

    func testCancelledStatusRepresentsInterruptedGroups() {
        let group = AssistantToolGroup(id: "group", tools: [
            makeTool(id: "done", state: .completed, isError: false),
            makeTool(id: "cancelled", state: .cancelled)
        ])

        XCTAssertEqual(group.status, .cancelled(total: 2))
    }

    func testOnlyActiveApprovalAndFailedGroupsPreferExpansion() {
        XCTAssertTrue(AssistantToolGroupStatus.running(completed: 0, total: 1).prefersExpanded)
        XCTAssertTrue(AssistantToolGroupStatus.approvalRequired.prefersExpanded)
        XCTAssertTrue(AssistantToolGroupStatus.failed(total: 1, failed: 1).prefersExpanded)
        XCTAssertFalse(AssistantToolGroupStatus.completed(total: 1).prefersExpanded)
        XCTAssertFalse(AssistantToolGroupStatus.cancelled(total: 1).prefersExpanded)
    }

    func testApprovalCannotBeHiddenByManualCollapse() {
        XCTAssertTrue(
            AssistantToolGroupStatus.approvalRequired.isExpanded(
                manualSelection: false
            )
        )
        XCTAssertFalse(
            AssistantToolGroupStatus.running(completed: 0, total: 1).isExpanded(
                manualSelection: false
            )
        )
    }

    func testTranscriptIsNearBottomWithinThreshold() {
        XCTAssertTrue(
            TranscriptScrollPresentation.isNearBottom(
                bottomY: 660,
                viewportHeight: 600,
                threshold: 72
            )
        )
        XCTAssertFalse(
            TranscriptScrollPresentation.isNearBottom(
                bottomY: 673,
                viewportHeight: 600,
                threshold: 72
            )
        )
    }

    func testConversationUsesToolGroupsAndManualScrollRecovery() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "PiWork/Features/Chat/Views/ChatView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("AssistantTranscriptPresentation.blocks(from: message.parts)"))
        XCTAssertTrue(source.contains("AssistantToolGroupView("))
        XCTAssertTrue(source.contains("TranscriptBottomPreferenceKey"))
        XCTAssertTrue(source.contains("TranscriptScrollPresentation.isNearBottom"))
        XCTAssertTrue(source.contains("L10n.string(\"chat.scroll_to_latest\")"))
        XCTAssertTrue(source.contains("AssistantThinkingView("))
        XCTAssertTrue(source.contains("chat.thinking.running"))
        XCTAssertFalse(source.contains("chat.thinking.completed"))
        XCTAssertTrue(source.contains("chat.thinking.title"))
        XCTAssertTrue(source.contains("accessibilityReduceMotion"))
        XCTAssertTrue(source.contains("State(initialValue: thinking.state == .running)"))

        let thinkingStart = try XCTUnwrap(source.range(of: "private struct AssistantThinkingView"))
        let toolGroupStart = try XCTUnwrap(source.range(of: "private struct AssistantToolGroupView"))
        let thinkingSource = String(source[thinkingStart.lowerBound..<toolGroupStart.lowerBound])
        XCTAssertTrue(thinkingSource.contains("Text(verbatim: thinking.text)"))
        XCTAssertFalse(thinkingSource.contains("Markdown(thinking.text)"))
        XCTAssertFalse(thinkingSource.contains(".transition("))
        XCTAssertFalse(thinkingSource.contains("withAnimation("))
    }

    func testConversationKeepsTranscriptRowsMountedWhileScrolling() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "PiWork/Features/Chat/Views/ChatView.swift"
            ),
            encoding: .utf8
        )

        let transcriptStart = try XCTUnwrap(source.range(of: "private var transcript: some View"))
        let emptySessionStart = try XCTUnwrap(source.range(of: "private var emptySession: some View"))
        let transcriptSource = String(source[transcriptStart.lowerBound..<emptySessionStart.lowerBound])

        XCTAssertTrue(transcriptSource.contains("VStack(alignment: .leading, spacing: 18)"))
        XCTAssertFalse(transcriptSource.contains("LazyVStack(alignment: .leading, spacing: 18)"))
    }

    func testToolGroupHeaderUsesLeadingAlignedContent() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "PiWork/Features/Chat/Views/ChatView.swift"
            ),
            encoding: .utf8
        )
        let toolGroupStart = try XCTUnwrap(
            source.range(of: "private struct AssistantToolGroupView")
        )
        let toolStepStart = try XCTUnwrap(
            source.range(of: "private struct AssistantToolStepRow")
        )
        let toolGroupSource = String(
            source[toolGroupStart.lowerBound..<toolStepStart.lowerBound]
        )
        let labelStart = try XCTUnwrap(toolGroupSource.range(of: "} label: {"))
        let expandedContentStart = try XCTUnwrap(
            toolGroupSource.range(of: "if isExpanded {")
        )
        let headerSource = String(
            toolGroupSource[labelStart.lowerBound..<expandedContentStart.lowerBound]
        )

        XCTAssertFalse(headerSource.contains("Spacer("))
        XCTAssertTrue(
            headerSource.contains(".frame(maxWidth: .infinity, alignment: .leading)")
        )
    }

    func testToolOnlyAssistantMessageHasNoCopyableText() {
        let message = PiChatMessage(
            message: SessionTranscriptMessage(
                id: "tool-only",
                role: .assistant,
                parts: [
                    .tool(makeTool(id: "read", state: .completed, isError: false))
                ],
                timestamp: "2026-08-09T15:19:00.000Z"
            )
        )

        XCTAssertEqual(message.copyableText, "")
        XCTAssertFalse(message.hasCopyableText)
    }

    func testCopyableTextOmitsTaggedThinkingContent() {
        let message = PiChatMessage(
            message: SessionTranscriptMessage(
                id: "legacy-thinking",
                role: .assistant,
                parts: [
                    .text(
                        id: "legacy",
                        text: "<think>Private working notes</think>\n\nVisible answer"
                    )
                ],
                timestamp: "2026-08-09T15:19:00.000Z"
            )
        )

        XCTAssertEqual(message.copyableText, "Visible answer")
    }

    func testCompletedThinkingWithoutDisplayableTextDoesNotCreateAVisibleMessage() {
        let message = PiChatMessage(
            message: SessionTranscriptMessage(
                id: "redacted-thinking",
                role: .assistant,
                parts: [
                    .thinking(
                        SessionThinkingRecord(
                            id: "thinking",
                            text: "",
                            state: .completed,
                            redacted: true
                        )
                    )
                ],
                timestamp: "2026-08-09T15:19:00.000Z"
            )
        )

        XCTAssertFalse(message.isVisible)
    }

    func testCopyableTextOmitsToolsBetweenAssistantTextBlocks() {
        let message = PiChatMessage(
            message: SessionTranscriptMessage(
                id: "mixed",
                role: .assistant,
                parts: [
                    .text(id: "before", text: "开始分析。"),
                    .tool(makeTool(id: "read", state: .completed, isError: false)),
                    .text(id: "after", text: "分析完成。")
                ],
                timestamp: "2026-08-09T15:19:00.000Z"
            )
        )

        XCTAssertEqual(message.copyableText, "开始分析。\n分析完成。")
        XCTAssertTrue(message.hasCopyableText)
    }

    func testAssistantMetadataIsRenderedOnlyForCopyableMessageText() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "PiWork/Features/Chat/Views/ChatView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(
            source.contains("guard message.hasCopyableText else { return nil }")
        )
        XCTAssertTrue(source.contains("MessageClipboard.copy(message.copyableText)"))
    }

    private func makeTool(
        id: String,
        state: SessionToolRunState,
        isError: Bool? = nil,
        approval: AgentHostApprovalRequest? = nil
    ) -> SessionToolRecord {
        SessionToolRecord(
            id: id,
            name: "read",
            summary: #"{"path":"README.md"}"#,
            state: state,
            isError: isError,
            approval: approval
        )
    }

    private func makeAssistantMessage(
        id: String,
        parts: [SessionTranscriptPart]
    ) -> PiChatMessage {
        PiChatMessage(
            message: SessionTranscriptMessage(
                id: id,
                role: .assistant,
                parts: parts,
                timestamp: "2026-08-10T12:00:00.000Z"
            )
        )
    }
}
