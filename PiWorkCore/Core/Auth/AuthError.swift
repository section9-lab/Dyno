import Foundation

public enum AuthError: Error {
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
    case invalidEmail
    case invalidEmailCode
}
