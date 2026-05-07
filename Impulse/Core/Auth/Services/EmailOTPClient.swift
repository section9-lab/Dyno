import CryptoKit
import Foundation
import Security

/// Drives Impulse's email-OTP login flow against the openauth issuer's
/// built-in `CodeProvider`. The provider exposes a stateful HTML form at
/// `/code/authorize` that issues / verifies the 6-digit code and finishes
/// with a 302 to the registered redirect URI carrying the OAuth `code`.
///
/// We never open a browser — instead we drive that form ourselves over an
/// ephemeral URLSession (so its cookie jar is in-memory only and dies with
/// the login attempt) and intercept the final 302 to read the auth code.
///
/// The auth code is then exchanged via the regular `OpenAuthClient.exchange`
/// path, so the resulting `AuthTokenSet` is byte-for-byte identical to one
/// obtained from the Google OAuth flow.
@MainActor
final class EmailOTPClient: NSObject {
    private let configuration: OpenAuthConfiguration
    private let openAuthClient: OpenAuthClient
    private let session: URLSession
    private let redirectURI: String

    private var pkceVerifier: String?
    private var expectedState: String?

    /// Loopback URL used as the OAuth redirect target. The HTTP server is
    /// never actually started — URLSession sees a 302 to this URL and we
    /// pluck the `code` parameter out of the Location header before any
    /// connection attempt completes. Port 1 is intentionally unbindable on
    /// macOS so even an accidental follow would fail fast.
    private static let loopbackRedirectURI = "http://127.0.0.1:1/callback"

    init(configuration: OpenAuthConfiguration = .current) {
        self.configuration = configuration
        self.openAuthClient = OpenAuthClient(configuration: configuration)

        // Ephemeral so cookies live only for this attempt — no risk of a
        // half-finished CodeProvider session leaking onto disk.
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        self.redirectURI = Self.loopbackRedirectURI

        self.session = URLSession(configuration: config)
        super.init()
    }

    /// Step 1: hit `/authorize?provider=code&...` to seed CodeProvider
    /// state, then POST `action=request` to make openauth call our
    /// `sendCode` callback (which mails the verification code via Resend).
    func requestCode(email: String) async throws {
        guard configuration.isConfigured else {
            throw AuthError.missingOpenAuthIssuer
        }

        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isLikelyEmail(trimmed) else {
            throw AuthError.invalidEmail
        }

        let pkce = try OTPPKCE.make()
        let state = try OTPPKCE.randomString(byteCount: 32)
        self.pkceVerifier = pkce.verifier
        self.expectedState = state

        try await beginAuthorize(state: state, challenge: pkce.challenge)
        try await postCodeForm(["action": "request", "email": trimmed])
    }

    /// Re-trigger the email send. CodeProvider treats `resend` the same as
    /// `request` in terms of state but flags the response so the UI can
    /// show a "code resent" hint. We don't surface that distinction here.
    func resendCode(email: String) async throws {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        try await postCodeForm(["action": "resend", "email": trimmed])
    }

    /// Step 2: POST `action=verify` with the code the user typed. On success
    /// openauth replies with a 302 to our redirect URI carrying `?code=...`
    /// and `?state=...`. We intercept that, pull the OAuth code, and run
    /// the standard token exchange.
    func verifyCode(_ code: String) async throws -> AuthTokenSet {
        guard let pkceVerifier, let expectedState else {
            throw AuthError.invalidCallback
        }

        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let callbackURL = try await postCodeFormExpectingRedirect([
            "action": "verify",
            "code": trimmedCode
        ])

        let authCode = try openAuthClient.authorizationCode(
            from: callbackURL,
            expectedState: expectedState
        )

        return try await openAuthClient.exchange(
            code: authCode,
            redirectURI: redirectURI,
            verifier: pkceVerifier
        )
    }

    // MARK: - Private

    private func beginAuthorize(state: String, challenge: String) async throws {
        var components = URLComponents(
            url: configuration.issuerURL.appendingPathComponent("authorize"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "provider", value: "code"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        guard let url = components?.url else {
            throw AuthError.invalidAuthorizationURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // openauth's CodeProvider returns the email-input form here; we don't
        // care about the body, only the cookies it sets.
        let (_, response) = try await dataAllowingFollow(for: request)
        try Self.assertNonError(response: response, body: nil)
    }

    private func postCodeForm(_ fields: [String: String]) async throws {
        let url = configuration.issuerURL.appendingPathComponent("code/authorize")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formURLEncoded(fields).data(using: .utf8)

        let (data, response) = try await dataAllowingFollow(for: request)
        try Self.assertNonError(response: response, body: data)
        try Self.assertNoCodeError(html: String(data: data, encoding: .utf8) ?? "")
    }

    /// Like `postCodeForm` but the response is expected to be a 302 to our
    /// loopback redirect URI. Returns that callback URL for code parsing.
    private func postCodeFormExpectingRedirect(_ fields: [String: String]) async throws -> URL {
        let url = configuration.issuerURL.appendingPathComponent("code/authorize")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formURLEncoded(fields).data(using: .utf8)

        let (data, response) = try await dataInterceptingRedirect(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           let location = httpResponse.value(forHTTPHeaderField: "Location"),
           let callback = URL(string: location, relativeTo: configuration.issuerURL)?.absoluteURL,
           callback.host == "127.0.0.1" {
            return callback
        }

        // No redirect → the form re-rendered with an error (most commonly
        // "invalid_code"). Surface a typed error for the UI.
        let html = String(data: data, encoding: .utf8) ?? ""
        try Self.assertNoCodeError(html: html)
        // Fallthrough: openauth replied 200 without an error marker we know.
        throw AuthError.invalidServerResponse
    }

    /// URLSession data task that follows redirects normally. Used for the
    /// initial GET (which returns 200) and the request POST (which returns
    /// 200 with the next form).
    private func dataAllowingFollow(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request, delegate: nil)
    }

    /// Variant that blocks redirect following so we can read the Location
    /// header from a 302. URLSession's redirect delegate must be configured
    /// per-task; we use a lightweight per-call delegate.
    private func dataInterceptingRedirect(for request: URLRequest) async throws -> (Data, URLResponse) {
        let delegate = NoRedirectDelegate()
        return try await session.data(for: request, delegate: delegate)
    }

    private static func formURLEncoded(_ parameters: [String: String]) -> String {
        parameters
            .map { "\($0.key.urlFormEncoded)=\($0.value.urlFormEncoded)" }
            .joined(separator: "&")
    }

    private static func assertNonError(response: URLResponse, body: Data?) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.invalidServerResponse
        }
        // 2xx and 3xx are fine — issuer often redirects internally.
        if (200..<400).contains(http.statusCode) { return }
        if let body, let text = String(data: body, encoding: .utf8) {
            throw AuthError.authorizationFailed("HTTP \(http.statusCode): \(text.prefix(200))")
        }
        throw AuthError.authorizationFailed("HTTP \(http.statusCode)")
    }

    /// CodeProvider re-renders the start form with `error=invalid_code` (or
    /// similar) when the user-entered code is wrong. We don't have a stable
    /// JSON channel, so we look for known markers in the HTML.
    private static func assertNoCodeError(html: String) throws {
        try EmailOTPValidation.assertNoCodeError(html: html)
    }

    private static func isLikelyEmail(_ candidate: String) -> Bool {
        EmailOTPValidation.isLikelyEmail(candidate)
    }
}

/// Pure-function helpers extracted so unit tests can exercise them without
/// spinning up a live URLSession or hitting the openauth issuer.
enum EmailOTPValidation {
    /// Lightweight email check matching what the issuer accepts: requires a
    /// non-empty local part, an `@`, and a TLD-bearing domain. We reject
    /// edge cases like leading/trailing dots in the domain so a typo
    /// surfaces inline before we burn a network round trip.
    static func isLikelyEmail(_ candidate: String) -> Bool {
        guard candidate.contains("@") else { return false }
        let parts = candidate.split(separator: "@", maxSplits: 1)
        guard parts.count == 2 else { return false }
        let local = parts[0]
        let domain = parts[1]
        return !local.isEmpty
            && domain.contains(".")
            && !domain.hasPrefix(".")
            && !domain.hasSuffix(".")
    }

    /// CodeProvider's HTML form re-renders with one of these error markers
    /// when the verification code is wrong. Match permissively because the
    /// exact wording is owned by the openauth library and may shift across
    /// versions. New markers should land here when discovered.
    static func assertNoCodeError(html: String) throws {
        let lower = html.lowercased()
        if lower.contains("invalid_code") || lower.contains("invalid code") {
            throw AuthError.invalidEmailCode
        }
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // nil tells URLSession to stop following and surface the redirect
        // response itself, which is exactly what we need to inspect Location.
        completionHandler(nil)
    }
}

private struct OTPPKCE {
    let verifier: String
    let challenge: String

    static func make() throws -> OTPPKCE {
        let verifier = try randomString(byteCount: 32)
        let digest = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(digest).otpBase64URLEncodedString()
        return OTPPKCE(verifier: verifier, challenge: challenge)
    }

    static func randomString(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        guard status == errSecSuccess else {
            throw AuthError.randomGenerationFailed(status)
        }
        return Data(bytes).otpBase64URLEncodedString()
    }
}

private extension String {
    var urlFormEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .otpURLFormAllowed) ?? self
    }
}

private extension CharacterSet {
    static let otpURLFormAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        return allowed
    }()
}

private extension Data {
    func otpBase64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
