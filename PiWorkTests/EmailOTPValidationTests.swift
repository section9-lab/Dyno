import XCTest
@testable import PiWork

/// Unit tests for the pure-function helpers behind email OTP login. The
/// network-driving parts of `EmailOTPClient` (HTML form posts, redirect
/// interception) require a live issuer to exercise meaningfully and are
/// covered separately by integration testing — here we lock in the input
/// validation and HTML error-marker matching that gate the network calls.
final class EmailOTPValidationTests: XCTestCase {
    // MARK: - Email shape

    func test_isLikelyEmail_acceptsCommonAddresses() {
        XCTAssertTrue(EmailOTPValidation.isLikelyEmail("user@example.com"))
        XCTAssertTrue(EmailOTPValidation.isLikelyEmail("a.b+tag@example.co.uk"))
        XCTAssertTrue(EmailOTPValidation.isLikelyEmail("123@qq.com"))
        XCTAssertTrue(EmailOTPValidation.isLikelyEmail("user@subdomain.example.com"))
    }

    func test_isLikelyEmail_rejectsMissingAtSign() {
        XCTAssertFalse(EmailOTPValidation.isLikelyEmail("userexample.com"))
    }

    func test_isLikelyEmail_rejectsEmptyLocalPart() {
        XCTAssertFalse(EmailOTPValidation.isLikelyEmail("@example.com"))
    }

    func test_isLikelyEmail_rejectsDomainWithoutDot() {
        // No TLD — single-label domains aren't reachable on the public
        // internet so we don't bother letting them through to the network.
        XCTAssertFalse(EmailOTPValidation.isLikelyEmail("user@localhost"))
    }

    func test_isLikelyEmail_rejectsDomainWithLeadingOrTrailingDot() {
        XCTAssertFalse(EmailOTPValidation.isLikelyEmail("user@.example.com"))
        XCTAssertFalse(EmailOTPValidation.isLikelyEmail("user@example.com."))
    }

    func test_isLikelyEmail_rejectsEmptyString() {
        XCTAssertFalse(EmailOTPValidation.isLikelyEmail(""))
    }

    func test_isLikelyEmail_acceptsLooseDomainsServerWillReject() {
        // The validator is intentionally permissive — it only rejects the
        // obviously broken inputs cheaply (no @, empty local, no dot in
        // domain). Edge cases like double @-signs end up with a
        // dot-bearing right-hand side that we accept and let the issuer
        // adjudicate. Pinning the current behavior here so a future
        // tightening is a deliberate change, not an accident.
        XCTAssertTrue(EmailOTPValidation.isLikelyEmail("a@@example.com"))
    }

    // MARK: - HTML error marker

    func test_assertNoCodeError_passesOnCleanHTML() {
        XCTAssertNoThrow(try EmailOTPValidation.assertNoCodeError(html: """
            <html><body><form><input name="code"></form></body></html>
        """))
    }

    func test_assertNoCodeError_throwsOnInvalidCodeMarker() {
        XCTAssertThrowsError(try EmailOTPValidation.assertNoCodeError(html: """
            <html><body class="error invalid_code">…</body></html>
        """)) { error in
            XCTAssertEqual(error as? AuthError, .invalidEmailCode)
        }
    }

    func test_assertNoCodeError_throwsOnHumanReadableInvalidCode() {
        // openauth library may also surface a friendlier rendering — match
        // the human-readable phrase regardless of casing.
        XCTAssertThrowsError(try EmailOTPValidation.assertNoCodeError(html: """
            <p>Invalid Code, please try again.</p>
        """)) { error in
            XCTAssertEqual(error as? AuthError, .invalidEmailCode)
        }
    }

    func test_assertNoCodeError_caseInsensitive() {
        XCTAssertThrowsError(try EmailOTPValidation.assertNoCodeError(html: "INVALID_CODE"))
        XCTAssertThrowsError(try EmailOTPValidation.assertNoCodeError(html: "INVALID CODE"))
    }
}

extension AuthError: Equatable {
    public static func == (lhs: AuthError, rhs: AuthError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidEmail, .invalidEmail),
             (.invalidEmailCode, .invalidEmailCode),
             (.missingOpenAuthIssuer, .missingOpenAuthIssuer),
             (.invalidAuthorizationURL, .invalidAuthorizationURL),
             (.invalidCallback, .invalidCallback),
             (.invalidState, .invalidState),
             (.missingAuthorizationCode, .missingAuthorizationCode),
             (.invalidServerResponse, .invalidServerResponse),
             (.invalidAccessToken, .invalidAccessToken):
            return true
        case (.authorizationFailed(let a), .authorizationFailed(let b)),
             (.tokenExchangeFailed(let a), .tokenExchangeFailed(let b)),
             (.webAuthenticationFailed(let a), .webAuthenticationFailed(let b)):
            return a == b
        case (.keychainFailure(let a), .keychainFailure(let b)),
             (.randomGenerationFailed(let a), .randomGenerationFailed(let b)):
            return a == b
        default:
            return false
        }
    }
}
