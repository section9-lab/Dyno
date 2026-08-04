import Foundation

extension URL {
    func agentDirectory() -> URL {
        self
    }

    func agentSkillsDirectory() -> URL {
        appendingPathComponent("skills", isDirectory: true)
    }

    func agentMemoryDirectory() -> URL {
        appendingPathComponent("memory", isDirectory: true)
    }
}
