import Foundation

extension URL {
    func agentDirectory() -> URL {
        self
    }

    func agentSessionDirectory() -> URL {
        appendingPathComponent("session", isDirectory: true)
    }

    func agentSkillsDirectory() -> URL {
        appendingPathComponent("skills", isDirectory: true)
    }

    func agentMemoryDirectory() -> URL {
        appendingPathComponent("memory", isDirectory: true)
    }
}
