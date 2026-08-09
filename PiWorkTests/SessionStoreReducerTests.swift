import XCTest
@testable import PiWork

final class SessionStoreReducerTests: XCTestCase {
    func testRunningEventBeforePromptResponseDoesNotRegressToSubmitting() {
        var reducer = SessionStoreReducer()
        reducer.apply(
            snapshot: makeSnapshot(sessionId: "session-one"),
            profile: .chat,
            sessionDirectory: "/tmp/sessions"
        )

        let effects = reducer.submitPrompt(
            sessionId: "session-one",
            turnId: "turn-one",
            text: "  Build\n the   feature  ",
            timestamp: "2026-08-09T00:00:01.000Z"
        )
        XCTAssertEqual(
            effects,
            [.renameSession(sessionId: "session-one", title: "Build the feature")]
        )
        XCTAssertEqual(reducer.records["session-one"]?.runState, .submitting)

        _ = reducer.receive(
            .sessionStateChanged(
                AgentHostSessionStateChangedPayload(
                    sessionId: "session-one",
                    sequence: 1,
                    turnId: "turn-one",
                    state: .running
                )
            ),
            timestamp: "2026-08-09T00:00:02.000Z"
        )
        reducer.promptAccepted(sessionId: "session-one", turnId: "turn-one")

        XCTAssertEqual(reducer.records["session-one"]?.runState, .running)
        XCTAssertEqual(reducer.records["session-one"]?.activeTurnId, "turn-one")
        XCTAssertEqual(reducer.records["session-one"]?.descriptor.title, "Build the feature")
        XCTAssertEqual(
            reducer.records["session-one"]?.messages.last?.content,
            [.text("  Build\n the   feature  ")]
        )
    }

    func testMessageDeltaIgnoresDuplicatesAndRequestsSnapshotForSequenceGap() {
        var reducer = SessionStoreReducer()
        reducer.apply(
            snapshot: makeSnapshot(sessionId: "session-one"),
            profile: .chat,
            sessionDirectory: nil
        )

        let firstEffects = reducer.receive(
            .sessionMessageDelta(
                AgentHostSessionMessageDeltaPayload(
                    sessionId: "session-one",
                    sequence: 1,
                    turnId: "turn-one",
                    delta: "Hello"
                )
            ),
            timestamp: "2026-08-09T00:00:01.000Z"
        )
        let duplicateEffects = reducer.receive(
            .sessionMessageDelta(
                AgentHostSessionMessageDeltaPayload(
                    sessionId: "session-one",
                    sequence: 1,
                    turnId: "turn-one",
                    delta: "Hello"
                )
            ),
            timestamp: "2026-08-09T00:00:02.000Z"
        )
        let gapEffects = reducer.receive(
            .sessionMessageDelta(
                AgentHostSessionMessageDeltaPayload(
                    sessionId: "session-one",
                    sequence: 3,
                    turnId: "turn-one",
                    delta: " skipped"
                )
            ),
            timestamp: "2026-08-09T00:00:03.000Z"
        )

        XCTAssertEqual(firstEffects, [])
        XCTAssertEqual(duplicateEffects, [])
        XCTAssertEqual(gapEffects, [.requestSnapshot(sessionId: "session-one")])
        XCTAssertEqual(reducer.records["session-one"]?.lastSequence, 1)
        XCTAssertEqual(
            reducer.records["session-one"]?.messages.last?.content,
            [.text("Hello")]
        )
    }

    func testEventsAreRoutedOnlyToTheirCorrelatedSession() {
        var reducer = SessionStoreReducer()
        reducer.apply(
            snapshot: makeSnapshot(sessionId: "session-one"),
            profile: .chat,
            sessionDirectory: nil
        )
        reducer.apply(
            snapshot: makeSnapshot(sessionId: "session-two"),
            profile: .chat,
            sessionDirectory: nil
        )

        _ = reducer.receive(
            .sessionStateChanged(
                AgentHostSessionStateChangedPayload(
                    sessionId: "session-two",
                    sequence: 1,
                    turnId: "turn-two",
                    state: .running
                )
            ),
            timestamp: "2026-08-09T00:00:01.000Z"
        )

        XCTAssertEqual(reducer.records["session-one"]?.runState, .idle)
        XCTAssertEqual(reducer.records["session-one"]?.lastSequence, 0)
        XCTAssertEqual(reducer.records["session-two"]?.runState, .running)
        XCTAssertEqual(reducer.records["session-two"]?.lastSequence, 1)
    }

    func testToolAndErrorEventsUpdateTheSessionRecord() {
        var reducer = SessionStoreReducer()
        reducer.apply(
            snapshot: makeSnapshot(sessionId: "session-one"),
            profile: .work,
            sessionDirectory: nil
        )

        _ = reducer.receive(
            .sessionToolStarted(
                AgentHostSessionToolStartedPayload(
                    sessionId: "session-one",
                    sequence: 1,
                    turnId: "turn-one",
                    toolCallId: "tool-one",
                    toolName: "read",
                    summary: #"{"path":"README.md"}"#
                )
            ),
            timestamp: "2026-08-09T00:00:01.000Z"
        )
        _ = reducer.receive(
            .sessionToolCompleted(
                AgentHostSessionToolCompletedPayload(
                    sessionId: "session-one",
                    sequence: 2,
                    turnId: "turn-one",
                    toolCallId: "tool-one",
                    toolName: "read",
                    isError: false
                )
            ),
            timestamp: "2026-08-09T00:00:02.000Z"
        )
        _ = reducer.receive(
            .sessionError(
                AgentHostSessionErrorPayload(
                    sessionId: "session-one",
                    sequence: 3,
                    turnId: "turn-one",
                    code: "agent_error",
                    message: "Model request failed"
                )
            ),
            timestamp: "2026-08-09T00:00:03.000Z"
        )

        XCTAssertEqual(
            reducer.records["session-one"]?.tools,
            [
                SessionToolRecord(
                    id: "tool-one",
                    name: "read",
                    summary: #"{"path":"README.md"}"#,
                    state: .completed,
                    isError: false
                )
            ]
        )
        XCTAssertEqual(reducer.records["session-one"]?.runState, .failed)
        XCTAssertEqual(reducer.records["session-one"]?.errorMessage, "Model request failed")
        XCTAssertNil(reducer.records["session-one"]?.activeTurnId)
    }

    func testTranscriptPreservesTextToolProgressAndFollowingTextOrder() throws {
        var reducer = SessionStoreReducer()
        reducer.apply(
            snapshot: makeSnapshot(sessionId: "session-one"),
            profile: .work,
            sessionDirectory: nil
        )

        _ = reducer.receive(
            .sessionMessageDelta(
                AgentHostSessionMessageDeltaPayload(
                    sessionId: "session-one",
                    sequence: 1,
                    turnId: "turn-one",
                    delta: "Before"
                )
            ),
            timestamp: "2026-08-09T00:00:01.000Z"
        )
        _ = reducer.receive(
            .sessionToolStarted(
                AgentHostSessionToolStartedPayload(
                    sessionId: "session-one",
                    sequence: 2,
                    turnId: "turn-one",
                    toolCallId: "tool-one",
                    toolName: "read",
                    summary: #"{"path":"README.md"}"#
                )
            ),
            timestamp: "2026-08-09T00:00:02.000Z"
        )
        _ = reducer.receive(
            .sessionToolUpdated(
                AgentHostSessionToolUpdatedPayload(
                    sessionId: "session-one",
                    sequence: 3,
                    turnId: "turn-one",
                    toolCallId: "tool-one",
                    toolName: "read",
                    output: "First line"
                )
            ),
            timestamp: "2026-08-09T00:00:03.000Z"
        )
        _ = reducer.receive(
            .sessionToolCompleted(
                AgentHostSessionToolCompletedPayload(
                    sessionId: "session-one",
                    sequence: 4,
                    turnId: "turn-one",
                    toolCallId: "tool-one",
                    toolName: "read",
                    output: "README contents",
                    isError: false
                )
            ),
            timestamp: "2026-08-09T00:00:04.000Z"
        )
        _ = reducer.receive(
            .sessionMessageDelta(
                AgentHostSessionMessageDeltaPayload(
                    sessionId: "session-one",
                    sequence: 5,
                    turnId: "turn-one",
                    delta: "After"
                )
            ),
            timestamp: "2026-08-09T00:00:05.000Z"
        )

        let parts = try XCTUnwrap(reducer.records["session-one"]?.transcript.last?.parts)
        XCTAssertEqual(parts.count, 3)
        guard case .text(_, let before) = parts[0],
              case .tool(let tool) = parts[1],
              case .text(_, let after) = parts[2] else {
            return XCTFail("Expected text, tool, text transcript parts")
        }
        XCTAssertEqual(before, "Before")
        XCTAssertEqual(tool.output, "README contents")
        XCTAssertEqual(tool.state, .completed)
        XCTAssertEqual(tool.isError, false)
        XCTAssertEqual(after, "After")
    }

    func testIdleStateMarksAnUnfinishedToolAsCancelled() throws {
        var reducer = SessionStoreReducer()
        reducer.apply(
            snapshot: makeSnapshot(sessionId: "session-one"),
            profile: .work,
            sessionDirectory: nil
        )
        _ = reducer.receive(
            .sessionToolStarted(
                AgentHostSessionToolStartedPayload(
                    sessionId: "session-one",
                    sequence: 1,
                    turnId: "turn-one",
                    toolCallId: "tool-one",
                    toolName: "bash",
                    summary: "sleep 10"
                )
            ),
            timestamp: "2026-08-09T00:00:01.000Z"
        )

        _ = reducer.receive(
            .sessionStateChanged(
                AgentHostSessionStateChangedPayload(
                    sessionId: "session-one",
                    sequence: 2,
                    turnId: "turn-one",
                    state: .idle
                )
            ),
            timestamp: "2026-08-09T00:00:02.000Z"
        )

        let tool = try XCTUnwrap(reducer.records["session-one"]?.tools.first)
        XCTAssertEqual(tool.state, .cancelled)
        XCTAssertNil(tool.approval)
    }

    func testSessionErrorFailsAnUnfinishedToolWithTheErrorMessage() throws {
        var reducer = SessionStoreReducer()
        reducer.apply(
            snapshot: makeSnapshot(sessionId: "session-one"),
            profile: .work,
            sessionDirectory: nil
        )
        _ = reducer.receive(
            .sessionToolStarted(
                AgentHostSessionToolStartedPayload(
                    sessionId: "session-one",
                    sequence: 1,
                    turnId: "turn-one",
                    toolCallId: "tool-one",
                    toolName: "bash",
                    summary: "bun test"
                )
            ),
            timestamp: "2026-08-09T00:00:01.000Z"
        )

        _ = reducer.receive(
            .sessionError(
                AgentHostSessionErrorPayload(
                    sessionId: "session-one",
                    sequence: 2,
                    turnId: "turn-one",
                    code: "agent_error",
                    message: "Model request failed"
                )
            ),
            timestamp: "2026-08-09T00:00:02.000Z"
        )

        let tool = try XCTUnwrap(reducer.records["session-one"]?.tools.first)
        XCTAssertEqual(tool.state, .completed)
        XCTAssertEqual(tool.isError, true)
        XCTAssertEqual(tool.output, "Model request failed")
        XCTAssertNil(tool.approval)
    }

    func testSnapshotProjectsToolResultIntoItsOriginalPosition() throws {
        let messages = [
            AgentHostSessionMessage(
                id: "assistant-before",
                role: .assistant,
                content: [
                    .text("Before"),
                    .toolCall(id: "tool-one", name: "read", argumentsSummary: #"{"path":"README.md"}"#)
                ],
                timestamp: "2026-08-09T00:00:01.000Z",
                provider: nil,
                model: nil,
                stopReason: nil,
                errorMessage: nil,
                toolCallId: nil,
                toolName: nil,
                isError: nil
            ),
            AgentHostSessionMessage(
                id: "tool-result",
                role: .tool,
                content: [.text("README contents")],
                timestamp: "2026-08-09T00:00:02.000Z",
                provider: nil,
                model: nil,
                stopReason: nil,
                errorMessage: nil,
                toolCallId: "tool-one",
                toolName: "read",
                isError: false
            ),
            AgentHostSessionMessage(
                id: "assistant-after",
                role: .assistant,
                content: [.text("After")],
                timestamp: "2026-08-09T00:00:03.000Z",
                provider: nil,
                model: nil,
                stopReason: nil,
                errorMessage: nil,
                toolCallId: nil,
                toolName: nil,
                isError: nil
            )
        ]
        var reducer = SessionStoreReducer()

        reducer.apply(
            snapshot: makeSnapshot(sessionId: "session-one", messages: messages),
            profile: .work,
            sessionDirectory: nil
        )

        let transcript = try XCTUnwrap(reducer.records["session-one"]?.transcript)
        let parts = transcript.flatMap(\.parts)
        XCTAssertEqual(parts.count, 3)
        guard case .text(_, let before) = parts[0],
              case .tool(let tool) = parts[1],
              case .text(_, let after) = parts[2] else {
            return XCTFail("Expected snapshot to preserve text, tool, text order")
        }
        XCTAssertEqual(before, "Before")
        XCTAssertEqual(tool.output, "README contents")
        XCTAssertEqual(tool.state, .completed)
        XCTAssertEqual(after, "After")
    }

    func testApprovalEventAddsPendingApprovalToItsCorrelatedWorkSession() {
        var reducer = SessionStoreReducer()
        reducer.apply(
            snapshot: makeSnapshot(sessionId: "session-one"),
            profile: .work,
            sessionDirectory: nil
        )

        let effects = reducer.receive(
            .sessionApprovalRequested(
                AgentHostSessionApprovalRequestedPayload(
                    sessionId: "session-one",
                    sequence: 1,
                    turnId: "turn-one",
                    requestId: "approval-one",
                    toolCallId: "tool-one",
                    toolName: "write",
                    summary: #"{"path":"Sources/App.swift"}"#
                )
            ),
            timestamp: "2026-08-09T00:00:01.000Z"
        )

        XCTAssertEqual(effects, [])
        XCTAssertEqual(
            reducer.records["session-one"]?.pendingApprovals,
            [
                AgentHostApprovalRequest(
                    id: "approval-one",
                    toolCallId: "tool-one",
                    toolName: "write",
                    summary: #"{"path":"Sources/App.swift"}"#
                )
            ]
        )
        XCTAssertEqual(reducer.records["session-one"]?.lastSequence, 1)
    }

    func testApprovalIsAttachedToItsToolInsideTheTranscript() throws {
        var reducer = SessionStoreReducer()
        reducer.apply(
            snapshot: makeSnapshot(sessionId: "session-one"),
            profile: .work,
            sessionDirectory: nil
        )

        _ = reducer.receive(
            .sessionToolStarted(
                AgentHostSessionToolStartedPayload(
                    sessionId: "session-one",
                    sequence: 1,
                    turnId: "turn-one",
                    toolCallId: "tool-one",
                    toolName: "write",
                    summary: #"{"path":"Sources/App.swift"}"#
                )
            ),
            timestamp: "2026-08-09T00:00:01.000Z"
        )
        let request = AgentHostSessionApprovalRequestedPayload(
            sessionId: "session-one",
            sequence: 2,
            turnId: "turn-one",
            requestId: "approval-one",
            toolCallId: "tool-one",
            toolName: "write",
            summary: #"{"path":"Sources/App.swift"}"#
        )
        _ = reducer.receive(
            .sessionApprovalRequested(request),
            timestamp: "2026-08-09T00:00:02.000Z"
        )

        let waitingTool = try XCTUnwrap(
            reducer.records["session-one"]?.transcript
                .flatMap(\.parts)
                .compactMap { part -> SessionToolRecord? in
                    guard case .tool(let tool) = part else { return nil }
                    return tool
                }
                .first
        )
        XCTAssertEqual(waitingTool.state, .awaitingApproval)
        XCTAssertEqual(waitingTool.approval, request.approval)

        reducer.resolveApproval(sessionId: "session-one", requestId: "approval-one")

        let resumedTool = try XCTUnwrap(
            reducer.records["session-one"]?.transcript
                .flatMap(\.parts)
                .compactMap { part -> SessionToolRecord? in
                    guard case .tool(let tool) = part else { return nil }
                    return tool
                }
                .first
        )
        XCTAssertEqual(resumedTool.state, .running)
        XCTAssertNil(resumedTool.approval)
    }

    func testSnapshotPendingApprovalCreatesAnInlineToolPart() throws {
        let approval = AgentHostApprovalRequest(
            id: "approval-one",
            toolCallId: "tool-one",
            toolName: "bash",
            summary: "bun test"
        )
        var reducer = SessionStoreReducer()

        reducer.apply(
            snapshot: makeSnapshot(
                sessionId: "session-one",
                pendingApprovals: [approval]
            ),
            profile: .work,
            sessionDirectory: nil
        )

        let tool = try XCTUnwrap(
            reducer.records["session-one"]?.transcript
                .flatMap(\.parts)
                .compactMap { part -> SessionToolRecord? in
                    guard case .tool(let tool) = part else { return nil }
                    return tool
                }
                .first
        )
        XCTAssertEqual(tool.state, .awaitingApproval)
        XCTAssertEqual(tool.approval, approval)
    }

    func testSelectingAccessModeAndResolvingApprovalUpdatesProjection() {
        var reducer = SessionStoreReducer()
        reducer.apply(
            snapshot: makeSnapshot(
                sessionId: "session-one",
                pendingApprovals: [
                    AgentHostApprovalRequest(
                        id: "approval-one",
                        toolCallId: "tool-one",
                        toolName: "bash",
                        summary: "bun test"
                    )
                ]
            ),
            profile: .work,
            sessionDirectory: nil
        )

        reducer.selectAccessMode(sessionId: "session-one", accessMode: .full)
        XCTAssertEqual(reducer.records["session-one"]?.pendingApprovals, [])
        let inlineTool = reducer.records["session-one"]?.transcript
            .flatMap(\.parts)
            .compactMap { part -> SessionToolRecord? in
                guard case .tool(let tool) = part else { return nil }
                return tool
            }
            .first
        XCTAssertEqual(inlineTool?.state, .running)
        XCTAssertNil(inlineTool?.approval)
        reducer.resolveApproval(sessionId: "session-one", requestId: "approval-one")

        XCTAssertEqual(reducer.records["session-one"]?.accessMode, .full)
        XCTAssertEqual(reducer.records["session-one"]?.pendingApprovals, [])
    }

    func testSelectingModelOptionUpdatesCapabilityStateAndContextBudget() {
        var reducer = SessionStoreReducer()
        reducer.apply(
            snapshot: makeSnapshot(sessionId: "session-one"),
            profile: .chat,
            sessionDirectory: nil
        )
        let model = AgentHostModel(
            provider: "openai",
            id: "gpt-5.6-sol",
            name: "GPT-5.6 Sol",
            contextWindow: 1_050_000,
            maxTokens: 128_000,
            reasoning: true,
            supportsImages: true
        )
        let usage = AgentHostContextUsage(
            tokens: 10_500,
            contextWindow: 1_050_000,
            percent: 1
        )
        let options = AgentHostModelOptions(
            fastMode: AgentHostModelOptionState(supported: true, enabled: true),
            oneMillionContext: AgentHostModelOptionState(supported: true, enabled: true)
        )

        reducer.selectModelOption(
            sessionId: "session-one",
            model: model,
            contextUsage: usage,
            modelOptions: options
        )

        XCTAssertEqual(reducer.records["session-one"]?.model, model)
        XCTAssertEqual(reducer.records["session-one"]?.contextUsage, usage)
        XCTAssertEqual(reducer.records["session-one"]?.modelOptions, options)
    }

    func testContextUsageFlowsFromSnapshotAndIdleEvent() {
        var reducer = SessionStoreReducer()
        let initialUsage = AgentHostContextUsage(
            tokens: 32_000,
            contextWindow: 128_000,
            percent: 25
        )
        let updatedUsage = AgentHostContextUsage(
            tokens: 96_000,
            contextWindow: 128_000,
            percent: 75
        )
        reducer.apply(
            snapshot: makeSnapshot(
                sessionId: "session-one",
                contextUsage: initialUsage
            ),
            profile: .chat,
            sessionDirectory: nil
        )

        let effects = reducer.receive(
            .sessionStateChanged(
                AgentHostSessionStateChangedPayload(
                    sessionId: "session-one",
                    sequence: 1,
                    turnId: "turn-one",
                    state: .idle,
                    contextUsage: updatedUsage
                )
            ),
            timestamp: "2026-08-09T00:00:01.000Z"
        )

        XCTAssertEqual(effects, [])
        XCTAssertEqual(reducer.records["session-one"]?.contextUsage, updatedUsage)
    }
}

private func makeSnapshot(
    sessionId: String,
    messages: [AgentHostSessionMessage] = [],
    pendingApprovals: [AgentHostApprovalRequest] = [],
    contextUsage: AgentHostContextUsage? = nil
) -> AgentHostSessionSnapshotResult {
    AgentHostSessionSnapshotResult(
        session: AgentHostSessionDescriptor(
            id: sessionId,
            path: "/tmp/\(sessionId).jsonl",
            cwd: "/tmp/project",
            title: "New Session"
        ),
        messages: messages,
        state: .idle,
        sequence: 0,
        turnId: nil,
        model: nil,
        contextUsage: contextUsage,
        thinkingLevel: .off,
        availableThinkingLevels: [],
        accessMode: .ask,
        pendingApprovals: pendingApprovals
    )
}
