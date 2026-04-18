import Foundation

extension URL {
    func agentDirectory() -> URL {
        appendingPathComponent(".agent", isDirectory: true)
    }

    func agentSessionDirectory() -> URL {
        agentDirectory().appendingPathComponent("session", isDirectory: true)
    }

    func agentSkillsDirectory() -> URL {
        agentDirectory().appendingPathComponent("skills", isDirectory: true)
    }
}
