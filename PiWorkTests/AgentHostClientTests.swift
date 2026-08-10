import Darwin
import XCTest
@testable import PiWork

final class AgentHostClientTests: XCTestCase {
    func testClientPassesPrivateAuthenticationPathToHostProcess() async throws {
        let script = #"printf '{"version":1,"kind":"event","event":"host.hello","payload":{"hostVersion":"%s","piVersion":"0.83.0","capabilities":[]}}\n' "$PI_WORK_AUTH_PATH"; cat >/dev/null"#
        let client = AgentHostClient(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            environment: ["PI_WORK_AUTH_PATH": "/tmp/pi-work/auth.json"]
        )

        let hello = try await client.start()

        XCTAssertEqual(hello.hostVersion, "/tmp/pi-work/auth.json")
        await client.stop()
    }

    func testClientDoesNotPassTestHarnessConfigurationToHostProcess() async throws {
        let script = #"printf '{"version":1,"kind":"event","event":"host.hello","payload":{"hostVersion":"%s","piVersion":"0.83.0","capabilities":[]}}\n' "${XCTestConfigurationFilePath:-missing}"; cat >/dev/null"#
        let client = AgentHostClient(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            environment: ["PI_WORK_AUTH_PATH": "/tmp/pi-work/auth.json"]
        )

        let hello = try await client.start()

        XCTAssertEqual(hello.hostVersion, "missing")
        await client.stop()
    }

    func testEventAndResponseAreDeliveredIndependentlyWhenInterleaved() async throws {
        let hello = #"{"version":1,"kind":"event","event":"host.hello","payload":{"hostVersion":"test-host","piVersion":"0.83.0","capabilities":["sessions.list"]}}"#
        let event = #"{"version":1,"kind":"event","event":"session.messageDelta","payload":{"sessionId":"session-one","sequence":2,"turnId":"turn-one","delta":"Hello"}}"#
        let response = #"{"version":1,"kind":"response","id":"list-1","ok":true,"result":{"sessions":[]}}"#
        let script = "printf '%s\\n' '\(hello)'; IFS= read -r _; printf '%s\\n' '\(event)'; printf '%s\\n' '\(response)'; cat >/dev/null"
        let client = AgentHostClient(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script]
        )

        _ = try await client.start()
        let events = await client.events()
        let eventTask = Task { () -> AgentHostServerEvent? in
            var iterator = events.makeAsyncIterator()
            return await iterator.next()
        }
        let result = try await client.request(
            id: "list-1",
            method: "sessions.list",
            params: AgentHostSessionListParameters(cwd: "/tmp/project", sessionDirectory: nil),
            as: AgentHostSessionListResult.self
        )

        XCTAssertEqual(result.sessions, [])
        let receivedEvent = await eventTask.value
        XCTAssertEqual(
            receivedEvent,
            .sessionMessageDelta(
                AgentHostSessionMessageDeltaPayload(
                    sessionId: "session-one",
                    sequence: 2,
                    turnId: "turn-one",
                    delta: "Hello"
                )
            )
        )
        await client.stop()
    }

    func testEventStreamFinishesWhenHostExits() async throws {
        let hello = #"{"version":1,"kind":"event","event":"host.hello","payload":{"hostVersion":"test-host","piVersion":"0.83.0","capabilities":[]}}"#
        let script = "printf '%s\\n' '\(hello)'; sleep 0.05; exit 0"
        let client = AgentHostClient(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script]
        )
        let stream = await client.events()
        let finished = expectation(description: "Event stream finishes")
        let reader = Task {
            for await _ in stream {}
            finished.fulfill()
        }

        _ = try await client.start()

        await fulfillment(of: [finished], timeout: 1)
        reader.cancel()
        await client.stop()
    }

    func testCancellingRequestFailsImmediatelyWithCancellationError() async throws {
        let hello = #"{"version":1,"kind":"event","event":"host.hello","payload":{"hostVersion":"test-host","piVersion":"0.83.0","capabilities":[]}}"#
        let script = "printf '%s\\n' '\(hello)'; IFS= read -r _; cat >/dev/null"
        let client = AgentHostClient(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script]
        )

        _ = try await client.start()
        let request = Task {
            try await client.request(
                id: "cancel-1",
                method: "sessions.list",
                params: AgentHostSessionListParameters(cwd: "/tmp/project", sessionDirectory: nil),
                timeout: 0.5,
                as: AgentHostSessionListResult.self
            )
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        request.cancel()

        do {
            _ = try await request.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        await client.stop()
    }

    func testConcurrentRequestsDecodeOutOfOrderResponsesByID() async throws {
        let hello = #"{"version":1,"kind":"event","event":"host.hello","payload":{"hostVersion":"test-host","piVersion":"0.83.0","capabilities":[]}}"#
        let secondResponse = #"{"version":1,"kind":"response","id":"second","ok":true,"result":{"value":"two"}}"#
        let firstResponse = #"{"version":1,"kind":"response","id":"first","ok":true,"result":{"value":"one"}}"#
        let script = "printf '%s\\n' '\(hello)'; IFS= read -r _; IFS= read -r _; printf '%s\\n' '\(secondResponse)'; printf '%s\\n' '\(firstResponse)'; cat >/dev/null"
        let client = AgentHostClient(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script]
        )

        _ = try await client.start()
        let first = Task {
            try await client.request(
                id: "first",
                method: "test.first",
                params: AgentHostClientTestParameters(),
                as: AgentHostClientTestResult.self
            )
        }
        let second = Task {
            try await client.request(
                id: "second",
                method: "test.second",
                params: AgentHostClientTestParameters(),
                as: AgentHostClientTestResult.self
            )
        }

        let firstResult = try await first.value
        let secondResult = try await second.value
        XCTAssertEqual(firstResult.value, "one")
        XCTAssertEqual(secondResult.value, "two")
        await client.stop()
    }

    func testStartReturnsTheHostHandshake() async throws {
        let hello = #"{"version":1,"kind":"event","event":"host.hello","payload":{"hostVersion":"test-host","piVersion":"0.83.0","capabilities":["sessions.list"]}}"#
        let script = "printf '%s\\n' '\(hello)'; cat >/dev/null"
        let client = AgentHostClient(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script]
        )

        let payload = try await client.start()

        XCTAssertEqual(payload.hostVersion, "test-host")
        XCTAssertEqual(payload.piVersion, "0.83.0")
        XCTAssertEqual(payload.capabilities, ["sessions.list"])
        await client.stop()
    }

    func testRequestCorrelatesAndDecodesTheMatchingResponse() async throws {
        let hello = #"{"version":1,"kind":"event","event":"host.hello","payload":{"hostVersion":"test-host","piVersion":"0.83.0","capabilities":["sessions.list"]}}"#
        let response = #"{"version":1,"kind":"response","id":"list-1","ok":true,"result":{"sessions":[{"id":"session-one","path":"/tmp/session.jsonl","cwd":"/tmp/project","title":"Session integration","firstMessage":"Implement sessions","messageCount":2,"createdAt":"2026-08-08T00:00:00.000Z","modifiedAt":"2026-08-08T00:01:00.000Z"}]}}"#
        let script = "printf '%s\\n' '\(hello)'; IFS= read -r _; printf '%s\\n' '\(response)'; cat >/dev/null"
        let client = AgentHostClient(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script]
        )

        _ = try await client.start()
        let result = try await client.request(
            id: "list-1",
            method: "sessions.list",
            params: AgentHostSessionListParameters(
                cwd: "/tmp/project",
                sessionDirectory: "/tmp/sessions"
            ),
            as: AgentHostSessionListResult.self
        )

        XCTAssertEqual(result.sessions.count, 1)
        XCTAssertEqual(result.sessions[0].id, "session-one")
        XCTAssertEqual(result.sessions[0].title, "Session integration")
        await client.stop()
    }

    func testRequestTimesOutWhenTheHostDoesNotRespond() async throws {
        let hello = #"{"version":1,"kind":"event","event":"host.hello","payload":{"hostVersion":"test-host","piVersion":"0.83.0","capabilities":["sessions.list"]}}"#
        let script = "printf '%s\\n' '\(hello)'; IFS= read -r _; cat >/dev/null"
        let client = AgentHostClient(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script]
        )

        _ = try await client.start()
        do {
            let _: AgentHostSessionListResult = try await client.request(
                id: "slow-1",
                method: "sessions.list",
                params: AgentHostSessionListParameters(cwd: "/tmp/project", sessionDirectory: nil),
                timeout: 0.05,
                as: AgentHostSessionListResult.self
            )
            XCTFail("Expected the request to time out")
        } catch AgentHostClientError.requestTimedOut(let id) {
            XCTAssertEqual(id, "slow-1")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        await client.stop()
    }

    func testStartTimesOutWhenTheHostDoesNotHandshake() async {
        let client = AgentHostClient(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "cat >/dev/null"],
            handshakeTimeout: 0.05
        )

        do {
            _ = try await client.start()
            XCTFail("Expected the handshake to time out")
        } catch AgentHostClientError.handshakeTimedOut {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        await client.stop()
    }

    func testHandshakeTimeoutKillsAHostThatIgnoresTermination() async throws {
        let markerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pi-work-stubborn-host-\(UUID().uuidString)")
        let script = "printf '%s' \"$$\" > '\(markerURL.path)'; trap '' TERM; while :; do sleep 1; done"
        let client = AgentHostClient(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            handshakeTimeout: 0.05
        )

        do {
            _ = try await client.start()
            XCTFail("Expected the handshake to time out")
        } catch AgentHostClientError.handshakeTimedOut {
            // Expected.
        }
        await client.stop()

        let pidText = try String(contentsOf: markerURL, encoding: .utf8)
        let pid = try XCTUnwrap(Int32(pidText))
        defer {
            Darwin.kill(pid, SIGKILL)
            try? FileManager.default.removeItem(at: markerURL)
        }
        for _ in 0..<20 where Darwin.kill(pid, 0) == 0 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        XCTAssertNotEqual(Darwin.kill(pid, 0), 0, "Timed-out host process must not survive")
    }

    func testStartRejectsAnIncompatibleHandshake() async {
        let hello = #"{"version":2,"kind":"event","event":"host.hello","payload":{"hostVersion":"future-host","piVersion":"0.83.0","capabilities":[]}}"#
        let script = "printf '%s\\n' '\(hello)'; cat >/dev/null"
        let client = AgentHostClient(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            handshakeTimeout: 0.2
        )

        do {
            _ = try await client.start()
            XCTFail("Expected an incompatible handshake error")
        } catch AgentHostClientError.invalidHandshake {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        await client.stop()
    }

    func testStartDrainsHostStandardErrorBeforeHandshake() async throws {
        let hello = #"{"version":1,"kind":"event","event":"host.hello","payload":{"hostVersion":"test-host","piVersion":"0.83.0","capabilities":[]}}"#
        let script = "head -c 1048576 /dev/zero >&2; printf '%s\\n' '\(hello)'; cat >/dev/null"
        let client = AgentHostClient(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            handshakeTimeout: 1
        )

        let payload = try await client.start()

        XCTAssertEqual(payload.hostVersion, "test-host")
        await client.stop()
    }

    func testRequestFailsImmediatelyWhenTheHostExits() async throws {
        let hello = #"{"version":1,"kind":"event","event":"host.hello","payload":{"hostVersion":"test-host","piVersion":"0.83.0","capabilities":["sessions.list"]}}"#
        let script = "printf '%s\\n' '\(hello)'; IFS= read -r _; exit 7"
        let client = AgentHostClient(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script]
        )

        _ = try await client.start()
        do {
            let _: AgentHostSessionListResult = try await client.request(
                id: "exit-1",
                method: "sessions.list",
                params: AgentHostSessionListParameters(cwd: "/tmp/project", sessionDirectory: nil),
                timeout: 1,
                as: AgentHostSessionListResult.self
            )
            XCTFail("Expected the host exit to fail the pending request")
        } catch AgentHostClientError.processExited(let status) {
            XCTAssertEqual(status, 7)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        await client.stop()
    }
}

private struct AgentHostClientTestParameters: Encodable {}

private struct AgentHostClientTestResult: Decodable {
    let value: String
}
