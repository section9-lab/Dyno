import Foundation

enum AgentHostClientError: Error {
    case alreadyRunning
    case invalidHandshake
    case handshakeTimedOut
    case notRunning
    case duplicateRequestID(String)
    case requestTimedOut(String)
    case requestFailed(code: String, message: String)
    case missingResponseResult
    case processExited(Int32)
}

actor AgentHostClient {
    private let executableURL: URL
    private let arguments: [String]
    private let environment: [String: String]
    private let handshakeTimeout: TimeInterval

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var framer = AgentHostLineFramer()
    private var handshakeContinuation: CheckedContinuation<AgentHostHelloPayload, Error>?
    private var handshakeTimeoutTask: Task<Void, Never>?
    private var pendingRequests: [String: CheckedContinuation<Data, Error>] = [:]
    private var requestTimeoutTasks: [String: Task<Void, Never>] = [:]
    private var serverEventStream: AsyncStream<AgentHostServerEvent>?
    private var serverEventContinuation: AsyncStream<AgentHostServerEvent>.Continuation?

    init(
        executableURL: URL,
        arguments: [String] = [],
        environment: [String: String] = [:],
        handshakeTimeout: TimeInterval = 5
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.handshakeTimeout = handshakeTimeout
    }

    func events() -> AsyncStream<AgentHostServerEvent> {
        if let serverEventStream {
            return serverEventStream
        }

        var continuation: AsyncStream<AgentHostServerEvent>.Continuation?
        let stream = AsyncStream<AgentHostServerEvent> { continuation = $0 }
        serverEventStream = stream
        serverEventContinuation = continuation
        return stream
    }

    func start() async throws -> AgentHostHelloPayload {
        guard process == nil else { throw AgentHostClientError.alreadyRunning }

        let task = Process()
        task.executableURL = executableURL
        task.arguments = arguments
        if !environment.isEmpty {
            task.environment = ProcessInfo.processInfo.environment.merging(environment) {
                _, override in override
            }
        }

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        task.standardInput = stdinPipe
        task.standardOutput = stdoutPipe
        task.standardError = stderrPipe

        stdinHandle = stdinPipe.fileHandleForWriting
        stdoutHandle = stdoutPipe.fileHandleForReading
        stderrHandle = stderrPipe.fileHandleForReading
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { await self?.consume(data) }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        task.terminationHandler = { [weak self] terminatedProcess in
            Task { await self?.processDidExit(terminatedProcess.terminationStatus) }
        }

        return try await withCheckedThrowingContinuation { continuation in
            handshakeContinuation = continuation
            do {
                try task.run()
                process = task
                let timeoutNanoseconds = UInt64(max(handshakeTimeout, 0) * 1_000_000_000)
                handshakeTimeoutTask = Task { [weak self] in
                    do {
                        try await Task.sleep(nanoseconds: timeoutNanoseconds)
                    } catch {
                        return
                    }
                    await self?.handshakeDidTimeout()
                }
            } catch {
                handshakeContinuation = nil
                handshakeTimeoutTask?.cancel()
                handshakeTimeoutTask = nil
                continuation.resume(throwing: error)
            }
        }
    }

    func stop() {
        handshakeTimeoutTask?.cancel()
        handshakeTimeoutTask = nil
        if let continuation = handshakeContinuation {
            handshakeContinuation = nil
            continuation.resume(throwing: CancellationError())
        }
        failPendingRequests(with: CancellationError())
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil
        try? stdinHandle?.close()
        if let process, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        cleanup()
    }

    func request<Parameters: Encodable, Result: Decodable>(
        id: String = UUID().uuidString,
        method: String,
        params: Parameters,
        timeout: TimeInterval = 30,
        as responseType: Result.Type
    ) async throws -> Result {
        guard let stdinHandle, process?.isRunning == true else {
            throw AgentHostClientError.notRunning
        }
        guard pendingRequests[id] == nil else {
            throw AgentHostClientError.duplicateRequestID(id)
        }

        let request = AgentHostRequest(id: id, method: method, params: params)
        let line = try request.encodedLine()
        let responseData = try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Data, Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                pendingRequests[id] = continuation
                requestTimeoutTasks[id] = Task { [weak self] in
                    do {
                        try await Task.sleep(nanoseconds: UInt64(max(timeout, 0) * 1_000_000_000))
                    } catch {
                        return
                    }
                    await self?.requestDidTimeout(id)
                }
                do {
                    try stdinHandle.write(contentsOf: line)
                } catch {
                    pendingRequests.removeValue(forKey: id)
                    requestTimeoutTasks.removeValue(forKey: id)?.cancel()
                    continuation.resume(throwing: error)
                }
            }
        }, onCancel: {
            Task { await self.requestWasCancelled(id) }
        })

        let response = try JSONDecoder().decode(AgentHostResponse<Result>.self, from: responseData)
        if !response.ok {
            throw AgentHostClientError.requestFailed(
                code: response.error?.code ?? "unknown",
                message: response.error?.message ?? "Agent Host request failed"
            )
        }
        guard let result = response.result else {
            throw AgentHostClientError.missingResponseResult
        }
        return result
    }

    private func consume(_ data: Data) {
        for record in framer.append(data) {
            guard let header = try? JSONDecoder().decode(AgentHostWireHeader.self, from: record) else {
                continue
            }

            if header.kind == "event", header.event == "host.hello",
               let continuation = handshakeContinuation {
                handshakeContinuation = nil
                handshakeTimeoutTask?.cancel()
                handshakeTimeoutTask = nil

                guard header.version == 1,
                      let event = try? JSONDecoder().decode(
                        AgentHostEvent<AgentHostHelloPayload>.self,
                        from: record
                      ) else {
                    continuation.resume(throwing: AgentHostClientError.invalidHandshake)
                    if let process, process.isRunning {
                        process.terminate()
                    }
                    cleanup()
                    continue
                }

                continuation.resume(returning: event.payload)
                continue
            }

            guard header.version == 1 else { continue }

            if header.kind == "event",
               let event = try? AgentHostServerEvent.decode(from: record) {
                serverEventContinuation?.yield(event)
                continue
            }

            if header.kind == "response", let id = header.id,
               let continuation = pendingRequests.removeValue(forKey: id) {
                requestTimeoutTasks.removeValue(forKey: id)?.cancel()
                continuation.resume(returning: record)
                continue
            }
        }
    }

    private func processDidExit(_ status: Int32) {
        handshakeTimeoutTask?.cancel()
        handshakeTimeoutTask = nil
        failPendingRequests(with: AgentHostClientError.processExited(status))
        serverEventContinuation?.finish()
        serverEventContinuation = nil
        if let continuation = handshakeContinuation {
            handshakeContinuation = nil
            continuation.resume(throwing: AgentHostClientError.processExited(status))
        }
        cleanup()
    }

    private func handshakeDidTimeout() {
        handshakeTimeoutTask = nil
        guard let continuation = handshakeContinuation else { return }
        handshakeContinuation = nil
        continuation.resume(throwing: AgentHostClientError.handshakeTimedOut)
        if let process, process.isRunning {
            process.terminate()
        }
        cleanup()
    }

    private func failPendingRequests(with error: Error) {
        let continuations = pendingRequests.values
        pendingRequests.removeAll()
        for task in requestTimeoutTasks.values {
            task.cancel()
        }
        requestTimeoutTasks.removeAll()
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
    }

    private func requestDidTimeout(_ id: String) {
        requestTimeoutTasks.removeValue(forKey: id)
        guard let continuation = pendingRequests.removeValue(forKey: id) else { return }
        continuation.resume(throwing: AgentHostClientError.requestTimedOut(id))
    }

    private func requestWasCancelled(_ id: String) {
        requestTimeoutTasks.removeValue(forKey: id)?.cancel()
        guard let continuation = pendingRequests.removeValue(forKey: id) else { return }
        continuation.resume(throwing: CancellationError())
    }

    private func cleanup() {
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil
        stdinHandle = nil
        stdoutHandle = nil
        stderrHandle = nil
        process = nil
        framer = AgentHostLineFramer()
    }
}
