import Foundation

struct AuthTokenSet: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: TimeInterval
    let issuedAt: Date

    var expiresAt: Date {
        issuedAt.addingTimeInterval(expiresIn)
    }
}
