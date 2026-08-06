import Foundation
import Combine
import os.log

/// Errors surfaced while locating or launching the bundled `pi` binary.
enum PiAgentProcessError: LocalizedError {
    case binaryNotFound
    case alreadyRunning
    case notRunning
    case encodingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "The bundled pi agent binary could not be found. Run scripts/fetch-pi-binary.sh and rebuild."
        case .alreadyRunning:
            return "This agent process is already running."
        case .notRunning:
            return "The agent process is not running."
        case .encodingFailed(let error):
            return "Failed to encode a command for the agent process: \(error.localizedDescription)"
        }
    }
}

/// Manages one long-lived `pi --mode rpc` subprocess for a single project
/// session. One instance per open session/tab; the process's working
/// directory is the project folder, so file tools (`read`/`edit`/`write`/
/// `bash`) operate on that project by default.
///
/// Communication follows the pi RPC protocol: line-delimited JSON on stdin
/// (commands) and stdout (responses + streaming events). See
/// `PiAgentProtocol.swift` and https://github.com/earendil-works/pi
/// `docs/rpc.md` for the wire format this implements.
@MainActor
final class PiAgentProcess: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?

    /// Fired for every decoded stdout line. Consumers (e.g. a chat view
    /// model) subscribe to update UI state; this class itself stays
    /// UI-agnostic beyond the `@Published` running/error flags.
    let messages = PassthroughSubject<PiAgentServerMessage, Never>()

    private let projectPath: String
    private let sessionDir: URL?
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutBuffer = Data()
    private let log = Logger(subsystem: "com.pi-work.app", category: "PiAgentProcess")

    init(projectPath: String, sessionDir: URL? = nil) {
        self.projectPath = projectPath
        self.sessionDir = sessionDir
    }

    /// Locates the architecture-appropriate bundled `pi` binary staged by
    /// `scripts/fetch-pi-binary.sh` into `PiWork/Resources/PiAgent/<arch>/`.
    static func bundledBinaryURL() -> URL? {
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x64"
        #endif
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let candidate = resourceURL.appendingPathComponent("PiAgent/\(arch)/pi")
        return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }

    func start() throws {
        guard process == nil else { throw PiAgentProcessError.alreadyRunning }
        guard let binaryURL = Self.bundledBinaryURL() else {
            throw PiAgentProcessError.binaryNotFound
        }

        let task = Process()
        task.executableURL = binaryURL
        task.currentDirectoryURL = URL(fileURLWithPath: projectPath, isDirectory: true)

        var arguments = ["--mode", "rpc"]
        if let sessionDir {
            arguments += ["--session-dir", sessionDir.path]
        }
        task.arguments = arguments

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        task.standardInput = stdinPipe
        task.standardOutput = stdoutPipe
        task.standardError = stderrPipe
        stdinHandle = stdinPipe.fileHandleForWriting

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            guard let self else { return }
            Task { @MainActor in
                self.consume(stdoutChunk: data)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Logger(subsystem: "com.pi-work.app", category: "PiAgentProcess")
                .error("pi stderr: \(text, privacy: .public)")
        }

        task.terminationHandler = { [weak self] proc in
            guard let self else { return }
            Task { @MainActor in
                self.isRunning = false
                self.process = nil
                if proc.terminationStatus != 0 {
                    self.lastError = "pi agent process exited with status \(proc.terminationStatus)"
                }
            }
        }

        try task.run()
        process = task
        isRunning = true
        lastError = nil
    }

    func stop() {
        process?.terminate()
        process = nil
        isRunning = false
        stdinHandle = nil
        stdoutBuffer.removeAll()
    }

    /// Sends one command to the agent's stdin. Throws if the process isn't
    /// running; callers should `start()` first (or check `isRunning`).
    func send(_ command: PiAgentCommand) throws {
        guard let stdinHandle else { throw PiAgentProcessError.notRunning }
        let line: Data
        do {
            line = try command.encodedLine()
        } catch {
            throw PiAgentProcessError.encodingFailed(error)
        }
        try stdinHandle.write(contentsOf: line)
    }

    /// Convenience for the common case: send a user prompt and get back an
    /// id you can correlate against the eventual `response`.
    @discardableResult
    func sendPrompt(_ text: String) throws -> String {
        let id = UUID().uuidString
        try send(.prompt(id: id, message: text))
        return id
    }

    // MARK: - stdout framing

    /// Accumulates raw stdout bytes and splits them into `\n`-delimited
    /// records per the RPC framing rules (LF-only; strip a trailing `\r`).
    private func consume(stdoutChunk chunk: Data) {
        stdoutBuffer.append(chunk)
        while let newlineIndex = stdoutBuffer.firstIndex(of: 0x0A) {
            var line = stdoutBuffer[stdoutBuffer.startIndex..<newlineIndex]
            stdoutBuffer.removeSubrange(stdoutBuffer.startIndex...newlineIndex)
            if line.last == 0x0D { line = line.dropLast() } // strip trailing \r
            guard !line.isEmpty else { continue }

            do {
                let message = try PiAgentMessageParser.parse(line: Data(line))
                messages.send(message)
            } catch {
                log.error("Failed to parse pi RPC line: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    deinit {
        process?.terminate()
    }
}
