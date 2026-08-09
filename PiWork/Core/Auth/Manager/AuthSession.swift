import Foundation
import SwiftUI

extension AuthError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingOpenAuthIssuer:
            return L10n.string("auth.error.missing_issuer")
        case .invalidAuthorizationURL:
            return L10n.string("auth.error.invalid_url")
        case .invalidCallback, .missingAuthorizationCode:
            return L10n.string("auth.error.invalid_callback")
        case .invalidState:
            return L10n.string("auth.error.state_mismatch")
        case .authorizationFailed(let message):
            return L10n.format("auth.error.authorization_failed", message)
        case .tokenExchangeFailed(let message):
            return L10n.format("auth.error.token_exchange_failed", message)
        case .invalidServerResponse:
            return L10n.string("auth.error.invalid_response")
        case .invalidAccessToken:
            return L10n.string("auth.error.invalid_credentials")
        case .keychainFailure(let status):
            return L10n.format("auth.error.keychain", Int(status))
        case .randomGenerationFailed(let status):
            return L10n.format("auth.error.random", Int(status))
        case .webAuthenticationFailed(let message):
            return L10n.format("auth.error.browser", message)
        case .invalidEmail:
            return L10n.string("auth.error.invalid_email")
        case .invalidEmailCode:
            return L10n.string("auth.error.invalid_code")
        }
    }
}

private struct OpenAuthSessionAuthorization {
    let callbackURL: URL
    let redirectURI: String
    let request: OpenAuthAuthorizationRequest
}

@MainActor
final class AuthSession: ObservableObject {
    static let shared = AuthSession()

    private static let isSignedInKey = "auth.isSignedIn"
    private static let providerKey = "auth.provider"
    private static let userKey = "auth.user"

    enum Provider: String, Codable {
        case google
        case email

        /// The `provider` query parameter the openauth issuer dispatches on.
        /// We keep `Provider` Swift-side names readable while preserving the
        /// exact string the issuer expects (the issuer registered the
        /// CodeProvider under the key "code").
        var issuerKey: String {
            switch self {
            case .google: return "google"
            case .email: return "code"
            }
        }

        /// Shown under the account name in the sidebar footer popover.
        var accountSubtitle: String {
            switch self {
            case .google:
                return L10n.string("account.google")
            case .email:
                return L10n.string("account.email")
            }
        }
    }

    @Published private(set) var isSignedIn: Bool {
        didSet {
            UserDefaults.standard.set(isSignedIn, forKey: Self.isSignedInKey)
        }
    }
    @Published private(set) var provider: Provider {
        didSet {
            UserDefaults.standard.set(provider.rawValue, forKey: Self.providerKey)
        }
    }
    @Published private(set) var user: AuthUser? {
        didSet {
            persistUser(user)
        }
    }
    @Published private(set) var isAuthenticating = false
    @Published private(set) var lastErrorMessage: String?

    /// Email of the address we just sent a code to. Drives the "code sent
    /// to <email>" hint in the verify step and is the source of truth for
    /// resends so the user can't change it mid-flow.
    @Published private(set) var pendingEmail: String?

    private let keychainStore = AuthKeychainStore()
    private let webAuthenticator = OAuthWebAuthenticator()

    /// Owns the PKCE state for one email-OTP attempt. Recreated on cancel
    /// or when a fresh request comes in. Nil whenever the user isn't mid-
    /// flow.
    private var pendingEmailClient: EmailOTPClient?

    private init() {
        self.user = Self.loadPersistedUser()
        self.isSignedIn = UserDefaults.standard.bool(forKey: Self.isSignedInKey)
        let storedProvider = UserDefaults.standard.string(forKey: Self.providerKey)
        self.provider = storedProvider.flatMap(Provider.init(rawValue:)) ?? .google
    }

    func restoreSessionOnLaunch() async {
        guard let tokens = try? keychainStore.load() else {
            isSignedIn = false
            user = nil
            return
        }

        let client = OpenAuthClient()
        do {
            if client.isAccessTokenValid(tokens.accessToken) {
                applyAuthenticatedUser(try client.user(from: tokens.accessToken))
            } else {
                let refreshed = try await client.refresh(refreshToken: tokens.refreshToken)
                try keychainStore.save(refreshed)
                applyAuthenticatedUser(try client.user(from: refreshed.accessToken))
            }
        } catch {
            try? keychainStore.delete()
            isSignedIn = false
            user = nil
            lastErrorMessage = error.localizedDescription
        }
    }

    func signInWithGoogle() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        lastErrorMessage = nil

        let client = OpenAuthClient()
        do {
            let authorization = try await authorizeWithGoogle(client: client)
            let code = try client.authorizationCode(
                from: authorization.callbackURL,
                expectedState: authorization.request.state
            )
            let tokens = try await client.exchange(
                code: code,
                redirectURI: authorization.redirectURI,
                verifier: authorization.request.verifier
            )

            try keychainStore.save(tokens)
            applyAuthenticatedUser(try client.user(from: tokens.accessToken))
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Email OTP login is split into two steps so the UI can show progress
    /// between "send code" and "verify code" and so we don't drag a long-
    /// lived task through both. Each call recreates the underlying client.
    func requestEmailCode(_ email: String) async throws {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        lastErrorMessage = nil

        let client = EmailOTPClient()
        do {
            try await client.requestCode(email: email)
            pendingEmailClient = client
            pendingEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    func resendEmailCode() async throws {
        guard let client = pendingEmailClient, let email = pendingEmail else {
            throw AuthError.invalidCallback
        }
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        lastErrorMessage = nil
        do {
            try await client.resendCode(email: email)
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    func verifyEmailCode(_ code: String) async throws {
        guard let client = pendingEmailClient else {
            throw AuthError.invalidCallback
        }
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        lastErrorMessage = nil
        do {
            let tokens = try await client.verifyCode(code)
            let openauth = OpenAuthClient()
            try keychainStore.save(tokens)
            applyAuthenticatedUser(try openauth.user(from: tokens.accessToken))
            cancelEmailLogin()
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    func cancelEmailLogin() {
        pendingEmailClient = nil
        pendingEmail = nil
    }

    /// Clear the surface-area error so a fresh step starts with a clean
    /// slate (e.g. switching from picker → email input shouldn't carry over
    /// a previous Google failure message).
    func clearLastError() {
        lastErrorMessage = nil
    }

    func signOut() {
        try? keychainStore.delete()
        user = nil
        isSignedIn = false
    }

    private func applyAuthenticatedUser(_ user: AuthUser) {
        self.user = user
        provider = Provider(rawValue: user.provider) ?? .google
        isSignedIn = true
        lastErrorMessage = nil
    }

    private func authorizeWithGoogle(client: OpenAuthClient) async throws -> OpenAuthSessionAuthorization {
        let authentication = try await webAuthenticator.authenticate { redirectURI in
            let request = try client.makeAuthorizationRequest(provider: "google", redirectURI: redirectURI)
            return OAuthWebAuthenticationRequest(
                authorizationURL: request.url,
                redirectURI: request.redirectURI,
                context: request
            )
        }

        return OpenAuthSessionAuthorization(
            callbackURL: authentication.callbackURL,
            redirectURI: authentication.redirectURI,
            request: authentication.context
        )
    }

    private static func loadPersistedUser() -> AuthUser? {
        guard let data = UserDefaults.standard.data(forKey: userKey) else {
            return nil
        }
        return try? JSONDecoder().decode(AuthUser.self, from: data)
    }

    private func persistUser(_ user: AuthUser?) {
        if let user, let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: Self.userKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.userKey)
        }
    }
}
