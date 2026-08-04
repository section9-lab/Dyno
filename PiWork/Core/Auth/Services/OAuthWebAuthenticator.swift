import AppKit
import Foundation
import Network

struct OAuthWebAuthenticationRequest<Context> {
    let authorizationURL: URL
    let redirectURI: String
    let context: Context
}

struct OAuthWebAuthenticationResult<Context> {
    let callbackURL: URL
    let redirectURI: String
    let context: Context
}

@MainActor
final class OAuthWebAuthenticator {
    private static let callbackTimeout: TimeInterval = 300

    private var callbackServer: OAuthLoopbackCallbackServer?

    func authenticate<Context>(makeRequest: (String) throws -> OAuthWebAuthenticationRequest<Context>) async throws -> OAuthWebAuthenticationResult<Context> {
        let server = try OAuthLoopbackCallbackServer()
        callbackServer = server

        do {
            let request = try makeRequest(server.redirectURI)
            try openAuthorizationURL(request.authorizationURL)

            let callbackURL = try await server.waitForCallback(timeout: Self.callbackTimeout)
            callbackServer = nil
            return OAuthWebAuthenticationResult(
                callbackURL: callbackURL,
                redirectURI: request.redirectURI,
                context: request.context
            )
        } catch {
            callbackServer = nil
            server.stop()
            throw error
        }
    }

    private func openAuthorizationURL(_ url: URL) throws {
        guard NSWorkspace.shared.open(url) else {
            throw AuthError.webAuthenticationFailed("Unable to open the default browser.")
        }
    }
}

private final class OAuthLoopbackCallbackServer: @unchecked Sendable {
    private enum Constants {
        static let callbackHost = "127.0.0.1"
        static let callbackPath = "/callback"
        static let listenerAttempts = 20
        static let maximumRequestBytes = 16 * 1024
        static let portRange: ClosedRange<UInt16> = 49152...65535
    }

    private let listener: NWListener
    private let port: NWEndpoint.Port
    private let queue = DispatchQueue(label: "com.section9lab.PiWork.oauth.loopback")
    private let lock = NSLock()

    private var completion: CheckedContinuation<URL, Error>?
    private var pendingResult: Result<URL, Error>?
    private var isFinished = false

    var redirectURI: String {
        "http://\(Constants.callbackHost):\(port.rawValue)\(Constants.callbackPath)"
    }

    init() throws {
        let endpoint = try Self.makeListener()
        listener = endpoint.listener
        port = endpoint.port

        listener.newConnectionHandler = { [weak self] connection in
            self?.receive(connection)
        }

        listener.stateUpdateHandler = { [weak self] state in
            guard case .failed(let error) = state else { return }
            self?.finish(.failure(AuthError.webAuthenticationFailed(error.localizedDescription)))
        }

        listener.start(queue: queue)
    }

    func waitForCallback(timeout: TimeInterval) async throws -> URL {
        try await withThrowingTaskGroup(of: URL.self) { group in
            group.addTask { try await self.waitForCallback() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw AuthError.webAuthenticationFailed("Timed out waiting for browser callback.")
            }

            guard let callbackURL = try await group.next() else {
                throw AuthError.invalidCallback
            }

            group.cancelAll()
            return callbackURL
        }
    }

    func stop() {
        listener.cancel()
    }

    private static func makeListener() throws -> (listener: NWListener, port: NWEndpoint.Port) {
        var lastError: Error?

        for _ in 0..<Constants.listenerAttempts {
            guard let port = NWEndpoint.Port(rawValue: UInt16.random(in: Constants.portRange)) else {
                continue
            }

            do {
                return (try NWListener(using: .tcp, on: port), port)
            } catch {
                lastError = error
            }
        }

        throw AuthError.webAuthenticationFailed(lastError?.localizedDescription ?? "Unable to create a local callback port.")
    }

    private func waitForCallback() async throws -> URL {
        try await withCheckedThrowingContinuation { completion in
            lock.lock()
            if let pendingResult {
                self.pendingResult = nil
                lock.unlock()
                completion.resume(with: pendingResult)
            } else {
                self.completion = completion
                lock.unlock()
            }
        }
    }

    private func receive(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: Constants.maximumRequestBytes) { [weak self] data, _, _, error in
            guard let self else { return }
            self.handleRequest(data: data, error: error, connection: connection)
        }
    }

    private func handleRequest(data: Data?, error: NWError?, connection: NWConnection) {
        if let error {
            sendResponse(.serverError("Unable to read OAuth callback."), on: connection)
            finish(.failure(AuthError.webAuthenticationFailed(error.localizedDescription)))
            return
        }

        guard let callbackURL = callbackURL(from: data) else {
            sendResponse(.badRequest("Invalid OAuth callback."), on: connection)
            finish(.failure(AuthError.invalidCallback))
            return
        }

        guard callbackURL.path == Constants.callbackPath else {
            sendResponse(.notFound, on: connection)
            return
        }

        sendResponse(.ok(Self.successHTML, contentType: "text/html; charset=utf-8"), on: connection)
        finish(.success(callbackURL))
    }

    private func callbackURL(from data: Data?) -> URL? {
        guard
            let data,
            let request = String(data: data, encoding: .utf8),
            let requestLine = request.components(separatedBy: "\r\n").first
        else {
            return nil
        }

        let parts = requestLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else { return nil }

        return URL(string: "http://\(Constants.callbackHost):\(port.rawValue)\(parts[1])")
    }

    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        guard !isFinished else {
            lock.unlock()
            return
        }

        isFinished = true
        if let completion {
            self.completion = nil
            lock.unlock()
            completion.resume(with: result)
        } else {
            pendingResult = result
            lock.unlock()
        }

        stop()
    }

    private func sendResponse(_ response: HTTPResponse, on connection: NWConnection) {
        connection.send(content: response.data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static let successHTML = """
    <!doctype html>
    <html lang="zh-CN">
      <head>
        <meta charset="utf-8">
        <title>pi-work 登录完成</title>
        <style>
          body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 48px; color: #202124; }
          main { max-width: 520px; margin: 0 auto; }
          h1 { font-size: 24px; margin-bottom: 12px; }
          p { line-height: 1.6; color: #5f6368; }
        </style>
      </head>
      <body>
        <main>
          <h1>pi-work 登录完成</h1>
          <p>可以关闭这个浏览器窗口并返回 pi-work。</p>
        </main>
      </body>
    </html>
    """
}

private struct HTTPResponse {
    let status: String
    let body: String
    let contentType: String

    static func ok(_ body: String, contentType: String) -> HTTPResponse {
        HTTPResponse(status: "200 OK", body: body, contentType: contentType)
    }

    static func badRequest(_ body: String) -> HTTPResponse {
        HTTPResponse(status: "400 Bad Request", body: body, contentType: "text/plain; charset=utf-8")
    }

    static func serverError(_ body: String) -> HTTPResponse {
        HTTPResponse(status: "500 Internal Server Error", body: body, contentType: "text/plain; charset=utf-8")
    }

    static let notFound = HTTPResponse(
        status: "404 Not Found",
        body: "Not found.",
        contentType: "text/plain; charset=utf-8"
    )

    var data: Data {
        let bodyData = Data(body.utf8)
        let header = "HTTP/1.1 \(status)\r\n"
            + "Content-Type: \(contentType)\r\n"
            + "Content-Length: \(bodyData.count)\r\n"
            + "Connection: close\r\n"
            + "\r\n"
        var response = Data(header.utf8)
        response.append(bodyData)
        return response
    }
}
