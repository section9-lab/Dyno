import XCTest
@testable import PiWork

final class AgentHostServiceTests: XCTestCase {
    func testCoreCapabilitiesRequirePromptImages() {
        XCTAssertTrue(AgentHostService.coreCapabilities.contains("session.promptImages"))
    }

    func testListsSlashCommandsFromTheRequestedLiveSession() async throws {
        let markerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pi-work-agent-host-commands-\(UUID().uuidString)")
        let hello = #"{"version":1,"kind":"event","event":"host.hello","payload":{"hostVersion":"test-host","piVersion":"0.83.0","capabilities":["session.commands"]}}"#
        let response = #"{"version":1,"kind":"response","id":"commands-one","ok":true,"result":{"commands":[{"name":"review","description":"Review changes","source":"extension"},{"name":"skill:ego-browser","description":"Browse websites","source":"skill"}]}}"#
        let script = "printf '%s\\n' '\(hello)'; IFS= read -r line; printf '%s\\n' \"$line\" > '\(markerURL.path)'; printf '%s\\n' '\(response)'; cat >/dev/null"
        let service = AgentHostService(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            requiredCapabilities: ["session.commands"]
        )

        let commands = try await service.listSlashCommands(
            sessionId: "session-one",
            requestID: "commands-one"
        )

        XCTAssertEqual(commands.map(\.name), ["review", "skill:ego-browser"])
        let request = try String(contentsOf: markerURL, encoding: .utf8)
        XCTAssertTrue(request.contains(#""method":"session.commands""#))
        XCTAssertTrue(request.contains(#""sessionId":"session-one""#))
        await service.stop()
        try? FileManager.default.removeItem(at: markerURL)
    }

    func testLifecycleReportsConnectionLossAndAutomaticRestartGeneration() async throws {
        let markerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pi-work-agent-host-lifecycle-\(UUID().uuidString)")
        let hello = #"{"version":1,"kind":"event","event":"host.hello","payload":{"hostVersion":"test-host","piVersion":"0.83.0","capabilities":[]}}"#
        let script = "if [ ! -e '\(markerURL.path)' ]; then touch '\(markerURL.path)'; printf '%s\\n' '\(hello)'; sleep 0.05; exit 9; fi; printf '%s\\n' '\(hello)'; cat >/dev/null"
        let service = AgentHostService(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            requiredCapabilities: []
        )
        let lifecycle = await service.lifecycleEvents()
        let received = Task { () -> [AgentHostServiceLifecycleEvent] in
            var iterator = lifecycle.makeAsyncIterator()
            var events: [AgentHostServiceLifecycleEvent] = []
            for _ in 0..<3 {
                if let event = await iterator.next() {
                    events.append(event)
                }
            }
            return events
        }

        _ = try await service.start()
        let lifecycleEvents = await received.value

        XCTAssertEqual(
            lifecycleEvents,
            [
                .connected(
                    generation: 1,
                    hello: AgentHostHelloPayload(
                        hostVersion: "test-host",
                        piVersion: "0.83.0",
                        capabilities: []
                    )
                ),
                .disconnected(generation: 1, error: .connectionLost),
                .restarted(
                    generation: 2,
                    hello: AgentHostHelloPayload(
                        hostVersion: "test-host",
                        piVersion: "0.83.0",
                        capabilities: []
                    )
                )
            ]
        )
        await service.stop()
        try? FileManager.default.removeItem(at: markerURL)
    }

    func testPromptIsNotReplayedAfterAutomaticHostRecovery() async throws {
        let launchMarkerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pi-work-agent-host-prompt-launch-\(UUID().uuidString)")
        let requestMarkerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pi-work-agent-host-prompt-request-\(UUID().uuidString)")
        let hello = #"{"version":1,"kind":"event","event":"host.hello","payload":{"hostVersion":"test-host","piVersion":"0.83.0","capabilities":["session.prompt"]}}"#
        let script = "if [ ! -e '\(launchMarkerURL.path)' ]; then touch '\(launchMarkerURL.path)'; printf '%s\\n' '\(hello)'; IFS= read -r line; printf '%s\\n' \"$line\" >> '\(requestMarkerURL.path)'; exit 9; fi; printf '%s\\n' '\(hello)'; cat >/dev/null"
        let service = AgentHostService(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            requiredCapabilities: ["session.prompt"]
        )

        do {
            _ = try await service.prompt(
                sessionId: "session-one",
                turnId: "turn-one",
                text: "Do this once",
                requestID: "prompt-once"
            )
            XCTFail("Expected the first Host process to exit")
        } catch AgentHostClientError.processExited(let status) {
            XCTAssertEqual(status, 9)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        try await Task.sleep(nanoseconds: 200_000_000)
        let requests = try String(contentsOf: requestMarkerURL, encoding: .utf8)
            .split(separator: "\n")
        XCTAssertEqual(requests.count, 1)

        await service.stop()
        try? FileManager.default.removeItem(at: launchMarkerURL)
        try? FileManager.default.removeItem(at: requestMarkerURL)
    }

    func testBundledServiceStartsStagedAgentHost() async throws {
        let service = try AgentHostService.bundled()

        let hello = try await service.start()

        XCTAssertTrue(Set(hello.capabilities).isSuperset(of: AgentHostService.coreCapabilities))
        await service.stop()
    }

    func testDefaultCapabilitySetRequiresCurrentSessionMethods() async {
        let hello = #"{"version":1,"kind":"event","event":"host.hello","payload":{"hostVersion":"test-host","piVersion":"0.83.0","capabilities":["sessions.list"]}}"#
        let script = "printf '%s\\n' '\(hello)'; cat >/dev/null"
        let service = AgentHostService(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script]
        )

        do {
            _ = try await service.start()
            XCTFail("Expected missing capabilities")
        } catch AgentHostServiceError.missingCapabilities(let capabilities) {
            XCTAssertEqual(
                capabilities,
                [
                    "auth.cancel",
                    "auth.logout",
                    "auth.respond",
                    "auth.start",
                    "extensions.install",
                    "extensions.listInstalled",
                    "extensions.remove",
                    "extensions.setEnabled",
                    "extensions.update",
                    "git.branches",
                    "models.list",
                    "providers.list",
                    "session.abort",
                    "session.close",
                    "session.commands",
                    "session.createDraft",
                    "session.delete",
                    "session.open",
                    "session.prompt",
                    "session.promptImages",
                    "session.rename",
                    "session.resolveApproval",
                    "session.setAccessMode",
                    "session.setGitBranch",
                    "session.setModel",
                    "session.setModelOption",
                    "session.setThinkingLevel",
                    "session.snapshot",
                    "session.toolOutput",
                    "session.transcriptPage",
                    "settings.get",
                    "settings.update"
                ]
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        await service.stop()
    }

    func testTypedMethodsUseTheCompleteSessionWireContract() async throws {
        let markerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pi-work-agent-host-requests-\(UUID().uuidString)")
        let capabilities = [
            "sessions.list",
            "models.list",
            "providers.list",
            "auth.start",
            "auth.respond",
            "auth.cancel",
            "auth.logout",
            "settings.get",
            "settings.update",
            "extensions.listInstalled",
            "extensions.install",
            "extensions.setEnabled",
            "extensions.update",
            "extensions.remove",
            "git.branches",
            "session.createDraft",
            "session.open",
            "session.snapshot",
            "session.transcriptPage",
            "session.toolOutput",
            "session.commands",
            "session.rename",
            "session.setGitBranch",
            "session.setAccessMode",
            "session.resolveApproval",
            "session.setModel",
            "session.setModelOption",
            "session.setThinkingLevel",
            "session.prompt",
            "session.promptImages",
            "session.abort",
            "session.close",
            "session.delete"
        ]
        let capabilitiesJSON = try String(
            data: JSONEncoder().encode(capabilities),
            encoding: .utf8
        )!
        let hello = #"{"version":1,"kind":"event","event":"host.hello","payload":{"hostVersion":"test-host","piVersion":"0.83.0","capabilities":\#(capabilitiesJSON)}}"#
        let responses = [
            #"{"version":1,"kind":"response","id":"list-one","ok":true,"result":{"sessions":[]}}"#,
            #"{"version":1,"kind":"response","id":"models-one","ok":true,"result":{"models":[]}}"#,
            #"{"version":1,"kind":"response","id":"git-one","ok":true,"result":{"available":true,"currentBranch":"main","branches":["main","feature"]}}"#,
            #"{"version":1,"kind":"response","id":"create-one","ok":true,"result":{"session":{"id":"session-one","path":"/tmp/session.jsonl","cwd":"/tmp/project","title":"New Session","firstMessage":"","messageCount":0,"createdAt":"2026-08-09T00:00:00.000Z","modifiedAt":"2026-08-09T00:00:00.000Z"}}}"#,
            #"{"version":1,"kind":"response","id":"open-one","ok":true,"result":{"sessionId":"session-one","path":"/tmp/session.jsonl","cwd":"/tmp/project"}}"#,
            #"{"version":1,"kind":"response","id":"snapshot-one","ok":true,"result":{"session":{"id":"session-one","path":"/tmp/session.jsonl","cwd":"/tmp/project","title":"New Session"},"messages":[],"state":"idle","sequence":0,"turnId":null,"model":null,"thinkingLevel":"high","availableThinkingLevels":["off","low","medium","high","max"],"modelOptions":{"fastMode":{"supported":false,"enabled":false},"oneMillionContext":{"supported":false,"enabled":false}},"accessMode":"ask","pendingApprovals":[]}}"#,
            #"{"version":1,"kind":"response","id":"history-one","ok":true,"result":{"sessionId":"session-one","messages":[],"revision":"revision-one","nextCursor":null,"hasMore":false}}"#,
            #"{"version":1,"kind":"response","id":"rename-one","ok":true,"result":{"sessionId":"session-one","title":"Renamed"}}"#,
            #"{"version":1,"kind":"response","id":"set-branch-one","ok":true,"result":{"sessionId":"session-one","branch":"feature"}}"#,
            #"{"version":1,"kind":"response","id":"set-model-one","ok":true,"result":{"sessionId":"session-one","model":{"provider":"openai","id":"gpt-test","name":"GPT Test","contextWindow":128000,"maxTokens":16384,"reasoning":true,"supportsImages":true,"supportsFastMode":false},"thinkingLevel":"high","availableThinkingLevels":["off","low","medium","high","max"],"modelOptions":{"fastMode":{"supported":true,"enabled":false},"oneMillionContext":{"supported":false,"enabled":false}}}}"#,
            #"{"version":1,"kind":"response","id":"set-thinking-one","ok":true,"result":{"sessionId":"session-one","thinkingLevel":"max","availableThinkingLevels":["off","low","medium","high","max"]}}"#,
            #"{"version":1,"kind":"response","id":"set-option-one","ok":true,"result":{"sessionId":"session-one","model":{"provider":"openai","id":"gpt-test","name":"GPT Test","contextWindow":128000,"maxTokens":16384,"reasoning":true,"supportsImages":true,"supportsFastMode":false},"contextUsage":null,"modelOptions":{"fastMode":{"supported":true,"enabled":true},"oneMillionContext":{"supported":false,"enabled":false}}}}"#,
            #"{"version":1,"kind":"response","id":"set-access-one","ok":true,"result":{"sessionId":"session-one","accessMode":"full"}}"#,
            #"{"version":1,"kind":"response","id":"resolve-one","ok":true,"result":{"sessionId":"session-one","requestId":"approval-one","decision":"allowOnce"}}"#,
            #"{"version":1,"kind":"response","id":"prompt-one","ok":true,"result":{"accepted":true,"sessionId":"session-one","turnId":"turn-one"}}"#,
            #"{"version":1,"kind":"response","id":"abort-one","ok":true,"result":{"aborted":true,"sessionId":"session-one"}}"#,
            #"{"version":1,"kind":"response","id":"close-one","ok":true,"result":{"closed":true,"sessionId":"session-one"}}"#,
            #"{"version":1,"kind":"response","id":"delete-one","ok":true,"result":{"deleted":true,"sessionId":"session-one"}}"#
        ]
        var script = "printf '%s\\n' '\(hello)'"
        for response in responses {
            script += "; IFS= read -r line; printf '%s\\n' \"$line\" >> '\(markerURL.path)'"
            script += "; printf '%s\\n' '\(response)'"
        }
        script += "; cat >/dev/null"
        let service = AgentHostService(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script]
        )

        let sessions = try await service.listSessions(
            cwd: "/tmp/project",
            sessionDirectory: "/tmp/sessions",
            requestID: "list-one"
        )
        let models = try await service.listModels(requestID: "models-one")
        let branches = try await service.gitBranches(
            cwd: "/tmp/project",
            requestID: "git-one"
        )
        let draft = try await service.createDraft(
            cwd: "/tmp/project",
            sessionDirectory: "/tmp/sessions",
            profile: .chat,
            requestID: "create-one"
        )
        let opened = try await service.openSession(
            path: "/tmp/session.jsonl",
            sessionDirectory: "/tmp/sessions",
            profile: .chat,
            requestID: "open-one"
        )
        let snapshot = try await service.snapshot(
            sessionId: "session-one",
            requestID: "snapshot-one"
        )
        let historyPage = try await service.transcriptPage(
            sessionId: "session-one",
            cursor: "cursor-one",
            limit: 40,
            requestID: "history-one"
        )
        let renamed = try await service.renameSession(
            sessionId: "session-one",
            title: "Renamed",
            requestID: "rename-one"
        )
        let selectedBranch = try await service.setGitBranch(
            sessionId: "session-one",
            branch: "feature",
            requestID: "set-branch-one"
        )
        let selectedModel = try await service.setModel(
            sessionId: "session-one",
            provider: "openai",
            modelId: "gpt-test",
            requestID: "set-model-one"
        )
        let selectedThinkingLevel = try await service.setThinkingLevel(
            sessionId: "session-one",
            thinkingLevel: .max,
            requestID: "set-thinking-one"
        )
        let selectedModelOption = try await service.setModelOption(
            sessionId: "session-one",
            option: .fastMode,
            enabled: true,
            requestID: "set-option-one"
        )
        let selectedAccessMode = try await service.setAccessMode(
            sessionId: "session-one",
            accessMode: .full,
            requestID: "set-access-one"
        )
        let resolvedApproval = try await service.resolveApproval(
            sessionId: "session-one",
            requestId: "approval-one",
            decision: .allowOnce,
            requestID: "resolve-one"
        )
        let prompt = try await service.prompt(
            sessionId: "session-one",
            turnId: "turn-one",
            text: "Hello",
            requestID: "prompt-one"
        )
        let abort = try await service.abort(
            sessionId: "session-one",
            requestID: "abort-one"
        )
        let close = try await service.closeSession(
            sessionId: "session-one",
            requestID: "close-one"
        )
        let deleted = try await service.deleteSession(
            sessionId: "session-one",
            cwd: "/tmp/project",
            sessionDirectory: "/tmp/sessions",
            requestID: "delete-one"
        )

        XCTAssertEqual(sessions, [])
        XCTAssertEqual(models, [])
        XCTAssertEqual(branches.currentBranch, "main")
        XCTAssertEqual(draft.id, "session-one")
        XCTAssertEqual(opened.sessionId, "session-one")
        XCTAssertEqual(snapshot.sequence, 0)
        XCTAssertEqual(historyPage.revision, "revision-one")
        XCTAssertEqual(renamed.title, "Renamed")
        XCTAssertEqual(selectedBranch.branch, "feature")
        XCTAssertEqual(selectedModel.model.id, "gpt-test")
        XCTAssertEqual(selectedThinkingLevel.thinkingLevel, .max)
        XCTAssertTrue(selectedModelOption.modelOptions.fastMode.enabled)
        XCTAssertEqual(selectedAccessMode.accessMode, .full)
        XCTAssertEqual(resolvedApproval.decision, .allowOnce)
        XCTAssertTrue(prompt.accepted)
        XCTAssertTrue(abort.aborted)
        XCTAssertTrue(close.closed)
        XCTAssertTrue(deleted.deleted)

        let requests = try String(contentsOf: markerURL, encoding: .utf8)
            .split(separator: "\n")
            .map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
        XCTAssertEqual(
            requests.compactMap { $0["method"] as? String },
            [
                "sessions.list",
                "models.list",
                "git.branches",
                "session.createDraft",
                "session.open",
                "session.snapshot",
                "session.transcriptPage",
                "session.rename",
                "session.setGitBranch",
                "session.setModel",
                "session.setThinkingLevel",
                "session.setModelOption",
                "session.setAccessMode",
                "session.resolveApproval",
                "session.prompt",
                "session.abort",
                "session.close",
                "session.delete"
            ]
        )
        XCTAssertEqual(
            (requests[2]["params"] as? [String: Any])?["cwd"] as? String,
            "/tmp/project"
        )
        XCTAssertEqual(
            (requests[3]["params"] as? [String: Any])?["profile"] as? String,
            "chat"
        )
        XCTAssertEqual(
            (requests[6]["params"] as? [String: Any])?["cursor"] as? String,
            "cursor-one"
        )
        XCTAssertEqual(
            (requests[6]["params"] as? [String: Any])?["limit"] as? Int,
            40
        )
        XCTAssertEqual(
            (requests[8]["params"] as? [String: Any])?["branch"] as? String,
            "feature"
        )
        XCTAssertEqual(
            (requests[10]["params"] as? [String: Any])?["thinkingLevel"] as? String,
            "max"
        )
        XCTAssertEqual(
            (requests[11]["params"] as? [String: Any])?["option"] as? String,
            "fastMode"
        )
        XCTAssertEqual(
            (requests[12]["params"] as? [String: Any])?["accessMode"] as? String,
            "full"
        )
        XCTAssertEqual(
            (requests[13]["params"] as? [String: Any])?["decision"] as? String,
            "allowOnce"
        )
        XCTAssertEqual(
            (requests[14]["params"] as? [String: Any])?["text"] as? String,
            "Hello"
        )
        XCTAssertEqual(
            (requests[17]["params"] as? [String: Any])?["cwd"] as? String,
            "/tmp/project"
        )

        await service.stop()
        try? FileManager.default.removeItem(at: markerURL)
    }

    func testRequestStartsHostLazily() async throws {
        let hello = #"{"version":1,"kind":"event","event":"host.hello","payload":{"hostVersion":"test-host","piVersion":"0.83.0","capabilities":["sessions.list"]}}"#
        let response = #"{"version":1,"kind":"response","id":"list-1","ok":true,"result":{"sessions":[]}}"#
        let script = "printf '%s\\n' '\(hello)'; IFS= read -r _; printf '%s\\n' '\(response)'; cat >/dev/null"
        let service = AgentHostService(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            requiredCapabilities: ["sessions.list"]
        )

        let result = try await service.request(
            id: "list-1",
            method: "sessions.list",
            params: AgentHostSessionListParameters(cwd: "/tmp/project", sessionDirectory: nil),
            as: AgentHostSessionListResult.self
        )

        XCTAssertEqual(result.sessions, [])
        await service.stop()
    }

    func testAgentSettingsMethodsUseTypedWireContract() async throws {
        let markerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pi-work-agent-settings-requests-\(UUID().uuidString)")
        let hello = #"{"version":1,"kind":"event","event":"host.hello","payload":{"hostVersion":"test-host","piVersion":"0.83.0","capabilities":["models.list","settings.get","settings.update"]}}"#
        let currentSettings = #"{"defaultModel":{"provider":"openai","modelId":"gpt-test"},"defaultThinkingLevel":"high","transport":"auto","compactionEnabled":true,"retryEnabled":true}"#
        let updatedSettings = #"{"defaultModel":{"provider":"openai","modelId":"gpt-test"},"defaultThinkingLevel":"max","transport":"auto","compactionEnabled":false,"retryEnabled":true}"#
        let responses = [
            #"{"version":1,"kind":"response","id":"models-one","ok":true,"result":{"models":[]}}"#,
            #"{"version":1,"kind":"response","id":"settings-get-one","ok":true,"result":\#(currentSettings)}"#,
            #"{"version":1,"kind":"response","id":"settings-update-one","ok":true,"result":\#(updatedSettings)}"#
        ]
        var script = "printf '%s\\n' '\(hello)'"
        for response in responses {
            script += "; IFS= read -r line; printf '%s\\n' \"$line\" >> '\(markerURL.path)'"
            script += "; printf '%s\\n' '\(response)'"
        }
        script += "; cat >/dev/null"
        let service = AgentHostService(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            requiredCapabilities: ["models.list", "settings.get", "settings.update"]
        )

        let models = try await service.listModels(requestID: "models-one")
        let settings = try await service.getAgentSettings(requestID: "settings-get-one")
        let updated = try await service.updateAgentSettings(
            AgentHostSettingsPatch(
                defaultThinkingLevel: .max,
                compactionEnabled: false
            ),
            requestID: "settings-update-one"
        )

        XCTAssertEqual(models, [])
        XCTAssertEqual(settings.defaultThinkingLevel, .high)
        XCTAssertEqual(updated.defaultThinkingLevel, .max)
        XCTAssertFalse(updated.compactionEnabled)

        let requests = try String(contentsOf: markerURL, encoding: .utf8)
            .split(separator: "\n")
            .map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
        XCTAssertEqual(
            requests.compactMap { $0["method"] as? String },
            ["models.list", "settings.get", "settings.update"]
        )
        let updateParams = try XCTUnwrap(requests[2]["params"] as? [String: Any])
        let patch = try XCTUnwrap(updateParams["patch"] as? [String: Any])
        XCTAssertEqual(patch["defaultThinkingLevel"] as? String, "max")
        XCTAssertEqual(patch["compactionEnabled"] as? Bool, false)

        await service.stop()
        try? FileManager.default.removeItem(at: markerURL)
    }

    func testInstalledExtensionMethodsUseTypedWireContract() async throws {
        let markerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pi-work-installed-extension-requests-\(UUID().uuidString)")
        let capabilities = [
            "extensions.listInstalled",
            "extensions.install",
            "extensions.setEnabled",
            "extensions.update",
            "extensions.remove"
        ]
        let capabilitiesJSON = try String(
            data: JSONEncoder().encode(capabilities),
            encoding: .utf8
        )!
        let hello = #"{"version":1,"kind":"event","event":"host.hello","payload":{"hostVersion":"test-host","piVersion":"0.83.0","capabilities":\#(capabilitiesJSON)}}"#
        let package = #"{"source":"npm:pi-tools","scope":"user","filtered":false,"installedPath":"/tmp/pi-tools","enabled":true}"#
        let responses = [
            #"{"version":1,"kind":"response","id":"extensions-list","ok":true,"result":{"packages":[\#(package)]}}"#,
            #"{"version":1,"kind":"response","id":"extensions-install","ok":true,"result":{"packages":[\#(package)]}}"#,
            #"{"version":1,"kind":"response","id":"extensions-disable","ok":true,"result":{"packages":[\#(package)]}}"#,
            #"{"version":1,"kind":"response","id":"extensions-update","ok":true,"result":{"packages":[\#(package)]}}"#,
            #"{"version":1,"kind":"response","id":"extensions-remove","ok":true,"result":{"packages":[]}}"#
        ]
        var script = "printf '%s\\n' '\(hello)'"
        for response in responses {
            script += "; IFS= read -r line; printf '%s\\n' \"$line\" >> '\(markerURL.path)'"
            script += "; printf '%s\\n' '\(response)'"
        }
        script += "; cat >/dev/null"
        let service = AgentHostService(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            requiredCapabilities: Set(capabilities)
        )

        let listed = try await service.listInstalledExtensions(requestID: "extensions-list")
        let installed = try await service.installExtension(
            source: "npm:pi-tools",
            requestID: "extensions-install"
        )
        let disabled = try await service.setInstalledExtensionEnabled(
            source: "npm:pi-tools",
            scope: .user,
            enabled: false,
            requestID: "extensions-disable"
        )
        let updated = try await service.updateInstalledExtension(
            source: "npm:pi-tools",
            scope: .user,
            requestID: "extensions-update"
        )
        let removed = try await service.removeInstalledExtension(
            source: "npm:pi-tools",
            scope: .user,
            requestID: "extensions-remove"
        )

        XCTAssertEqual(listed.first?.source, "npm:pi-tools")
        XCTAssertEqual(installed.first?.source, "npm:pi-tools")
        XCTAssertEqual(disabled.first?.source, "npm:pi-tools")
        XCTAssertEqual(updated.first?.installedPath, "/tmp/pi-tools")
        XCTAssertTrue(removed.isEmpty)

        let requests = try String(contentsOf: markerURL, encoding: .utf8)
            .split(separator: "\n")
            .map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
        XCTAssertEqual(
            requests.compactMap { $0["method"] as? String },
            [
                "extensions.listInstalled",
                "extensions.install",
                "extensions.setEnabled",
                "extensions.update",
                "extensions.remove"
            ]
        )
        let installParams = try XCTUnwrap(requests[1]["params"] as? [String: Any])
        XCTAssertEqual(installParams["source"] as? String, "npm:pi-tools")
        let enabledParams = try XCTUnwrap(requests[2]["params"] as? [String: Any])
        XCTAssertEqual(enabledParams["enabled"] as? Bool, false)
        let updateParams = try XCTUnwrap(requests[3]["params"] as? [String: Any])
        XCTAssertEqual(updateParams["source"] as? String, "npm:pi-tools")
        XCTAssertEqual(updateParams["scope"] as? String, "user")

        await service.stop()
        try? FileManager.default.removeItem(at: markerURL)
    }

    func testServiceForwardsClientEvents() async throws {
        let hello = #"{"version":1,"kind":"event","event":"host.hello","payload":{"hostVersion":"test-host","piVersion":"0.83.0","capabilities":["sessions.list"]}}"#
        let event = #"{"version":1,"kind":"event","event":"session.stateChanged","payload":{"sessionId":"session-one","sequence":1,"turnId":"turn-one","state":"running"}}"#
        let response = #"{"version":1,"kind":"response","id":"list-1","ok":true,"result":{"sessions":[]}}"#
        let script = "printf '%s\\n' '\(hello)'; IFS= read -r _; printf '%s\\n' '\(event)'; printf '%s\\n' '\(response)'; cat >/dev/null"
        let service = AgentHostService(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            requiredCapabilities: ["sessions.list"]
        )
        let events = await service.events()
        let eventTask = Task { () -> AgentHostServerEvent? in
            var iterator = events.makeAsyncIterator()
            return await iterator.next()
        }

        let _: AgentHostSessionListResult = try await service.request(
            id: "list-1",
            method: "sessions.list",
            params: AgentHostSessionListParameters(cwd: "/tmp/project", sessionDirectory: nil),
            as: AgentHostSessionListResult.self
        )

        let receivedEvent = await eventTask.value
        XCTAssertEqual(
            receivedEvent,
            .sessionStateChanged(
                AgentHostSessionStateChangedPayload(
                    sessionId: "session-one",
                    sequence: 1,
                    turnId: "turn-one",
                    state: .running
                )
            )
        )
        await service.stop()
    }

    func testServiceBroadcastsEventsToEverySubscriber() async throws {
        let hello = #"{"version":1,"kind":"event","event":"host.hello","payload":{"hostVersion":"test-host","piVersion":"0.83.0","capabilities":["sessions.list"]}}"#
        let event = #"{"version":1,"kind":"event","event":"models.changed","payload":{"reason":"authentication","providerId":"openai-codex"}}"#
        let response = #"{"version":1,"kind":"response","id":"list-1","ok":true,"result":{"sessions":[]}}"#
        let script = "printf '%s\\n' '\(hello)'; IFS= read -r _; printf '%s\\n' '\(event)'; printf '%s\\n' '\(response)'; cat >/dev/null"
        let service = AgentHostService(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            requiredCapabilities: ["sessions.list"]
        )
        let firstEvents = await service.events()
        let secondEvents = await service.events()
        let firstReceived = expectation(description: "first event subscriber receives the event")
        let secondReceived = expectation(description: "second event subscriber receives the event")
        let expected = AgentHostServerEvent.modelsChanged(
            AgentHostModelsChangedPayload(reason: .authentication, providerId: "openai-codex")
        )
        let firstTask = Task {
            var iterator = firstEvents.makeAsyncIterator()
            if await iterator.next() == expected { firstReceived.fulfill() }
        }
        let secondTask = Task {
            var iterator = secondEvents.makeAsyncIterator()
            if await iterator.next() == expected { secondReceived.fulfill() }
        }

        let _: AgentHostSessionListResult = try await service.request(
            id: "list-1",
            method: "sessions.list",
            params: AgentHostSessionListParameters(cwd: "/tmp/project", sessionDirectory: nil),
            as: AgentHostSessionListResult.self
        )

        await fulfillment(of: [firstReceived, secondReceived], timeout: 0.5)
        firstTask.cancel()
        secondTask.cancel()
        await service.stop()
    }

    func testAuthenticationMethodsUseTypedWireContract() async throws {
        let capabilities = ["providers.list", "auth.start", "auth.respond", "auth.cancel", "auth.logout"]
        let capabilitiesJSON = try String(
            data: JSONEncoder().encode(capabilities),
            encoding: .utf8
        )!
        let hello = #"{"version":1,"kind":"event","event":"host.hello","payload":{"hostVersion":"test-host","piVersion":"0.83.0","capabilities":\#(capabilitiesJSON)}}"#
        let provider = #"{"id":"openai-codex","name":"OpenAI Codex","methods":[{"type":"oauth","name":"OpenAI Codex OAuth"}],"status":{"configured":false,"source":null,"credentialType":null,"canDisconnect":false},"models":{"total":4,"available":0}}"#
        let responses = [
            #"{"version":1,"kind":"response","id":"providers-one","ok":true,"result":{"providers":[\#(provider)]}}"#,
            #"{"version":1,"kind":"response","id":"start-one","ok":true,"result":{"accepted":true,"flowId":"flow-one"}}"#,
            #"{"version":1,"kind":"response","id":"respond-one","ok":true,"result":{"accepted":true}}"#,
            #"{"version":1,"kind":"response","id":"cancel-one","ok":true,"result":{"cancelRequested":true}}"#,
            #"{"version":1,"kind":"response","id":"logout-one","ok":true,"result":{"removed":false,"provider":\#(provider)}}"#
        ]
        var script = "printf '%s\\n' '\(hello)'"
        for response in responses {
            script += "; IFS= read -r line; printf '%s\\n' '\(response)'"
        }
        script += "; cat >/dev/null"
        let service = AgentHostService(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            requiredCapabilities: Set(capabilities)
        )

        let providers = try await service.listProviders(requestID: "providers-one")
        let started = try await service.startAuthentication(
            flowId: "flow-one",
            providerId: "openai-codex",
            method: .oauth,
            requestID: "start-one"
        )
        let responded = try await service.respondToAuthentication(
            flowId: "flow-one",
            promptId: "prompt-one",
            value: "browser",
            requestID: "respond-one"
        )
        let cancelled = try await service.cancelAuthentication(
            flowId: "flow-one",
            requestID: "cancel-one"
        )
        let loggedOut = try await service.logoutProvider(
            providerId: "openai-codex",
            requestID: "logout-one"
        )

        XCTAssertEqual(providers.first?.id, "openai-codex")
        XCTAssertTrue(started.accepted)
        XCTAssertTrue(responded.accepted)
        XCTAssertTrue(cancelled.cancelRequested)
        XCTAssertFalse(loggedOut.removed)
        await service.stop()
    }

    func testServiceRestartsHostOnceAfterUnexpectedExit() async throws {
        let markerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pi-work-agent-host-\(UUID().uuidString)")
        let hello = #"{"version":1,"kind":"event","event":"host.hello","payload":{"hostVersion":"test-host","piVersion":"0.83.0","capabilities":["sessions.list"]}}"#
        let response = #"{"version":1,"kind":"response","id":"list-after-restart","ok":true,"result":{"sessions":[]}}"#
        let script = "if [ ! -e '\(markerURL.path)' ]; then touch '\(markerURL.path)'; printf '%s\\n' '\(hello)'; sleep 0.05; exit 9; fi; printf '%s\\n' '\(hello)'; IFS= read -r _; printf '%s\\n' '\(response)'; cat >/dev/null"
        let service = AgentHostService(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            requiredCapabilities: ["sessions.list"]
        )

        _ = try await service.start()
        try await Task.sleep(nanoseconds: 200_000_000)
        let result: AgentHostSessionListResult = try await service.request(
            id: "list-after-restart",
            method: "sessions.list",
            params: AgentHostSessionListParameters(cwd: "/tmp/project", sessionDirectory: nil),
            as: AgentHostSessionListResult.self
        )

        XCTAssertEqual(result.sessions, [])
        await service.stop()
        try? FileManager.default.removeItem(at: markerURL)
    }

    func testConcurrentStartsShareOneHostLaunch() async throws {
        let launchesURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pi-work-agent-host-launches-\(UUID().uuidString)")
        let hello = #"{"version":1,"kind":"event","event":"host.hello","payload":{"hostVersion":"test-host","piVersion":"0.83.0","capabilities":[]}}"#
        let script = "printf 'launch\\n' >> '\(launchesURL.path)'; sleep 0.1; printf '%s\\n' '\(hello)'; sleep 0.2; exit 0"
        let service = AgentHostService(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            requiredCapabilities: []
        )

        async let first = service.start()
        async let second = service.start()
        _ = try await (first, second)

        let launches = try String(contentsOf: launchesURL, encoding: .utf8)
            .split(separator: "\n")
        XCTAssertEqual(launches.count, 1)
        await service.stop()
        try? FileManager.default.removeItem(at: launchesURL)
    }

    func testStoppedServiceCannotStartAnotherHost() async throws {
        let hello = #"{"version":1,"kind":"event","event":"host.hello","payload":{"hostVersion":"test-host","piVersion":"0.83.0","capabilities":[]}}"#
        let script = "printf '%s\\n' '\(hello)'; cat >/dev/null"
        let service = AgentHostService(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            requiredCapabilities: []
        )

        _ = try await service.start()
        await service.stop()

        do {
            _ = try await service.start()
            XCTFail("Expected stopped service error")
        } catch AgentHostServiceError.stopped {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        await service.stop()
    }

    func testStopDuringStartupPreventsLateClientInstallation() async throws {
        let hello = #"{"version":1,"kind":"event","event":"host.hello","payload":{"hostVersion":"test-host","piVersion":"0.83.0","capabilities":[]}}"#
        let script = "sleep 0.2; printf '%s\\n' '\(hello)'; cat >/dev/null"
        let service = AgentHostService(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            requiredCapabilities: []
        )
        let startup = Task {
            try await service.start()
        }

        try await Task.sleep(nanoseconds: 50_000_000)
        await service.stop()

        do {
            _ = try await startup.value
            XCTFail("Expected startup cancellation")
        } catch is CancellationError {
            // Expected.
        } catch AgentHostServiceError.stopped {
            // Also valid if the handshake completed at the stop boundary.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAutomaticRecoveryDoesNotEnterRestartLoop() async throws {
        let launchesURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pi-work-agent-host-recovery-\(UUID().uuidString)")
        let hello = #"{"version":1,"kind":"event","event":"host.hello","payload":{"hostVersion":"test-host","piVersion":"0.83.0","capabilities":[]}}"#
        let script = "printf 'launch\\n' >> '\(launchesURL.path)'; printf '%s\\n' '\(hello)'; sleep 0.05; exit 9"
        let service = AgentHostService(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            requiredCapabilities: []
        )

        _ = try await service.start()
        try await Task.sleep(nanoseconds: 250_000_000)

        let launches = try String(contentsOf: launchesURL, encoding: .utf8)
            .split(separator: "\n")
        XCTAssertEqual(launches.count, 2)
        await service.stop()
        try? FileManager.default.removeItem(at: launchesURL)
    }

    func testServiceRecoversWhenHostExitsImmediatelyAfterHandshake() async throws {
        let markerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pi-work-agent-host-immediate-exit-\(UUID().uuidString)")
        let hello = #"{"version":1,"kind":"event","event":"host.hello","payload":{"hostVersion":"test-host","piVersion":"0.83.0","capabilities":["sessions.list"]}}"#
        let response = #"{"version":1,"kind":"response","id":"after-immediate-exit","ok":true,"result":{"sessions":[]}}"#
        let script = "if [ ! -e '\(markerURL.path)' ]; then touch '\(markerURL.path)'; printf '%s\\n' '\(hello)'; exit 9; fi; printf '%s\\n' '\(hello)'; IFS= read -r _; printf '%s\\n' '\(response)'; cat >/dev/null"
        let service = AgentHostService(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            requiredCapabilities: ["sessions.list"]
        )

        _ = try await service.start()
        try await Task.sleep(nanoseconds: 150_000_000)
        let result: AgentHostSessionListResult = try await service.request(
            id: "after-immediate-exit",
            method: "sessions.list",
            params: AgentHostSessionListParameters(cwd: "/tmp/project", sessionDirectory: nil),
            as: AgentHostSessionListResult.self
        )

        XCTAssertEqual(result.sessions, [])
        await service.stop()
        try? FileManager.default.removeItem(at: markerURL)
    }

    func testStartRejectsHostMissingRequiredCapability() async {
        let hello = #"{"version":1,"kind":"event","event":"host.hello","payload":{"hostVersion":"test-host","piVersion":"0.83.0","capabilities":["sessions.list"]}}"#
        let script = "printf '%s\\n' '\(hello)'; cat >/dev/null"
        let service = AgentHostService(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            requiredCapabilities: ["sessions.list", "session.prompt"]
        )

        do {
            _ = try await service.start()
            XCTFail("Expected missing capabilities")
        } catch AgentHostServiceError.missingCapabilities(let capabilities) {
            XCTAssertEqual(capabilities, ["session.prompt"])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        await service.stop()
    }
}
