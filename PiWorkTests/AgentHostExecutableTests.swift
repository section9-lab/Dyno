import XCTest
@testable import PiWork

final class AgentHostExecutableTests: XCTestCase {
    func testAgentSettingsDirectoryLivesInPiWorkApplicationSupport() {
        let applicationSupport = URL(fileURLWithPath: "/Users/test/Library/Application Support")

        let result = AgentHostExecutable.agentDirectoryURL(
            applicationSupportDirectory: applicationSupport
        )

        XCTAssertEqual(
            result.path,
            "/Users/test/Library/Application Support/pi-work/Agent"
        )
        XCTAssertFalse(result.path.contains("/.pi/"))
    }

    func testAuthenticationFileLivesInPiWorkApplicationSupport() {
        let applicationSupport = URL(fileURLWithPath: "/Users/test/Library/Application Support")

        let result = AgentHostExecutable.authenticationFileURL(
            applicationSupportDirectory: applicationSupport
        )

        XCTAssertEqual(
            result.path,
            "/Users/test/Library/Application Support/pi-work/Agent/auth.json"
        )
        XCTAssertFalse(result.path.contains("/.pi/"))
    }

    func testBuildStagesTheSelfContainedAgentHostAndBunPackageManager() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let configuration = try String(
            contentsOf: repositoryRoot.appendingPathComponent("project.yml"),
            encoding: .utf8
        )

        XCTAssertTrue(configuration.contains("Stage bundled agent host"))
        XCTAssertTrue(configuration.contains("Stage bundled Bun package manager"))
        XCTAssertTrue(configuration.contains("scripts/fetch-bun-binary.sh"))
        XCTAssertFalse(configuration.contains("Stage bundled pi agent binary"))
    }

    func testResolveFindsOnlyAnExecutableInContentsHelpers() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let appURL = root.appendingPathComponent("PiWork.app", isDirectory: true)
        let helperURL = appURL.appendingPathComponent(
            "Contents/Helpers/AgentHost/arm64/pi-work-agent-host",
            isDirectory: false
        )
        try FileManager.default.createDirectory(
            at: helperURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: helperURL)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertNil(AgentHostExecutable.resolve(in: appURL, architecture: "arm64"))

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: helperURL.path
        )

        XCTAssertEqual(
            AgentHostExecutable.resolve(in: appURL, architecture: "arm64"),
            helperURL
        )
    }

    func testResolveBunFindsOnlyAnExecutableInContentsHelpers() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let appURL = root.appendingPathComponent("PiWork.app", isDirectory: true)
        let bunURL = appURL.appendingPathComponent(
            "Contents/Helpers/Bun/arm64/bun",
            isDirectory: false
        )
        try FileManager.default.createDirectory(
            at: bunURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: bunURL)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertNil(AgentHostExecutable.resolveBun(in: appURL, architecture: "arm64"))

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: bunURL.path
        )

        XCTAssertEqual(
            AgentHostExecutable.resolveBun(in: appURL, architecture: "arm64"),
            bunURL
        )
    }
}
