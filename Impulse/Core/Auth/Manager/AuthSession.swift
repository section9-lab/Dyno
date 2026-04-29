import Foundation
import SwiftUI

enum AuthError: LocalizedError {
    case missingOpenAuthIssuer
    case invalidAuthorizationURL
    case invalidCallback
    case invalidState
    case missingAuthorizationCode
    case authorizationFailed(String)
    case tokenExchangeFailed(String)
    case invalidServerResponse
    case invalidAccessToken
    case keychainFailure(OSStatus)
    case randomGenerationFailed(OSStatus)
    case webAuthenticationFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingOpenAuthIssuer:
            return L10n.tr("auth.error.missing_issuer")
        case .invalidAuthorizationURL:
            return L10n.tr("auth.error.invalid_authorization_url")
        case .invalidCallback, .missingAuthorizationCode:
            return L10n.tr("auth.error.invalid_callback")
        case .invalidState:
            return L10n.tr("auth.error.invalid_state")
        case .authorizationFailed(let message):
            return L10n.tr("auth.error.authorization_failed", message)
        case .tokenExchangeFailed(let message):
            return L10n.tr("auth.error.token_exchange_failed", message)
        case .invalidServerResponse:
            return L10n.tr("auth.error.invalid_server_response")
        case .invalidAccessToken:
            return L10n.tr("auth.error.invalid_access_token")
        case .keychainFailure(let status):
            return L10n.tr("auth.error.keychain", Int(status))
        case .randomGenerationFailed(let status):
            return L10n.tr("auth.error.random", Int(status))
        case .webAuthenticationFailed(let message):
            return L10n.tr("auth.error.web_authentication_failed", message)
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
        case alipay

        var accountTitleKey: LocalizedStringKey {
            switch self {
            case .google:
                return "account.google_user"
            case .alipay:
                return "account.alipay_user"
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

    private let keychainStore = AuthKeychainStore()
    private let webAuthenticator = OAuthWebAuthenticator()

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

    func signInWithAlipayPlaceholder() {
        lastErrorMessage = L10n.tr("auth.error.alipay_unavailable")
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
