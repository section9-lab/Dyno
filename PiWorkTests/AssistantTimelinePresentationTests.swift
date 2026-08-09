import XCTest
@testable import PiWork

final class AssistantTimelinePresentationTests: XCTestCase {
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

        XCTAssertTrue(source.contains("if message.hasCopyableText"))
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
}
