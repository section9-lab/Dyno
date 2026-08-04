import Foundation

public enum EmailOTPValidation {
    public static func isLikelyEmail(_ candidate: String) -> Bool {
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

    public static func assertNoCodeError(html: String) throws {
        let lower = html.lowercased()
        if lower.contains("invalid_code") || lower.contains("invalid code") {
            throw AuthError.invalidEmailCode
        }
    }
}
