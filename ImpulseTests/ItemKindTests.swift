import XCTest
import SwiftData
@testable import Impulse

final class ItemKindTests: XCTestCase {

    /// Raw values are persisted in the SwiftData store and in JSON
    /// (ProjectSnapshot). Renaming a case is allowed; changing its raw value
    /// silently breaks every existing user's chat history. This test pins the
    /// on-disk contract so that any rename shows up in code review.
    func test_rawValuesArePinned() {
        XCTAssertEqual(ItemKind.userMessage.rawValue, "user_message")
        XCTAssertEqual(ItemKind.assistantMessage.rawValue, "assistant_message")
        XCTAssertEqual(ItemKind.toolExecution.rawValue, "tool_execution")
        XCTAssertEqual(ItemKind.compactionSummary.rawValue, "compaction_summary")
    }

    func test_allCasesCoversFourKinds() {
        XCTAssertEqual(ItemKind.allCases.count, 4)
    }

    /// Forward-compat: a future version may write a kind we don't recognise.
    /// `Item.kindEnum` must NOT crash; degrade to `.assistantMessage` so the
    /// row still renders as a regular message.
    func test_unknownKindFallsBackToAssistantMessage() throws {
        let container = try ModelContainer(
            for: StoredSession.self,
            configurations: .init(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let session = StoredSession(id: "s1", projectPath: "/p", title: "t", startedAt: Date())
        context.insert(session)
        let message = StoredMessage(timestamp: Date(), role: "assistant", content: "hi", session: session)
        context.insert(message)
        try context.save()

        let item = Item(
            id: message.persistentModelID,
            timestamp: Date(),
            content: "future content",
            isUser: false,
            kind: "image_attachment_v2", // hypothetical future kind
            conversationID: "s1",
            projectPath: "/p"
        )
        XCTAssertEqual(item.kindEnum, .assistantMessage)
    }

    // MARK: - SwiftData entity → Item projection

    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let container = try ModelContainer(
            for: StoredSession.self,
            configurations: .init(isStoredInMemoryOnly: true)
        )
        return (container, ModelContext(container))
    }

    func test_userMessageProjection() throws {
        let (_, context) = try makeContext()
        let session = StoredSession(id: "s1", projectPath: "/p", title: "t", startedAt: Date())
        context.insert(session)
        let m = StoredMessage(timestamp: Date(), role: "user", content: "hello", session: session)
        context.insert(m)
        try context.save()

        let item = m.toItem()
        XCTAssertTrue(item.isUser)
        XCTAssertEqual(item.kindEnum, .userMessage)
        XCTAssertEqual(item.content, "hello")
        XCTAssertEqual(item.conversationID, "s1")
        XCTAssertEqual(item.projectPath, "/p")
    }

    func test_assistantMessageProjection() throws {
        let (_, context) = try makeContext()
        let session = StoredSession(id: "s2", projectPath: "/q", title: "t", startedAt: Date())
        context.insert(session)
        let m = StoredMessage(timestamp: Date(), role: "assistant", content: "hi back", session: session)
        context.insert(m)
        try context.save()

        let item = m.toItem()
        XCTAssertFalse(item.isUser)
        XCTAssertEqual(item.kindEnum, .assistantMessage)
    }

    func test_toolRunProjection() throws {
        let (_, context) = try makeContext()
        let session = StoredSession(id: "s3", projectPath: "/r", title: "t", startedAt: Date())
        context.insert(session)
        let run = StoredToolRun(
            id: "call-abc",
            timestamp: Date(),
            toolName: "read",
            status: "success",
            summary: "/some/file (file)",
            output: "file contents",
            session: session
        )
        context.insert(run)
        try context.save()

        let item = run.toItem()
        XCTAssertNotNil(item)
        XCTAssertFalse(item!.isUser)
        XCTAssertEqual(item!.kindEnum, .toolExecution)
        // Tool runs serialize as JSON-encoded PersistedToolExecution.
        let payload = try JSONDecoder().decode(
            PersistedToolExecution.self,
            from: Data(item!.content.utf8)
        )
        XCTAssertEqual(payload.id, "call-abc")
        XCTAssertEqual(payload.toolName, "read")
        XCTAssertEqual(payload.status, "success")
    }

    func test_compactionSummaryProjection() throws {
        let (_, context) = try makeContext()
        let session = StoredSession(id: "s4", projectPath: "/s", title: "t", startedAt: Date())
        context.insert(session)
        let s = StoredCompactionSummary(
            timestamp: Date(),
            content: "summary text",
            session: session
        )
        context.insert(s)
        try context.save()

        let item = s.toItem()
        XCTAssertFalse(item.isUser)
        XCTAssertEqual(item.kindEnum, .compactionSummary)
        XCTAssertEqual(item.content, "summary text")
    }

    /// `StoredMessage.kind` must mirror `role` so callers don't need to
    /// rebuild the enum manually.
    func test_storedMessageKindReflectsRole() {
        let session = StoredSession(id: "s", projectPath: "/p", title: "t", startedAt: Date())
        let user = StoredMessage(timestamp: Date(), role: "user", content: "x", session: session)
        let assistant = StoredMessage(timestamp: Date(), role: "assistant", content: "y", session: session)
        XCTAssertEqual(user.kind, .userMessage)
        XCTAssertEqual(assistant.kind, .assistantMessage)
        XCTAssertTrue(user.isUser)
        XCTAssertFalse(assistant.isUser)
    }
}
