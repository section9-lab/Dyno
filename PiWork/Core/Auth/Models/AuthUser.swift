import Foundation

struct AuthUser: Codable, Equatable {
    let id: String
    let provider: String
    let email: String
    let name: String
    let avatarURL: URL?

    var displayName: String {
        if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return email
    }

    var avatarInitial: String {
        let source = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return source.first.map { String($0).uppercased() } ?? "G"
    }
}
