import Foundation

enum AgentHostExecutable {
    static let filename = "pi-work-agent-host"
    static let bunFilename = "bun"

    #if arch(arm64)
    private static let currentArchitecture = "arm64"
    #elseif arch(x86_64)
    private static let currentArchitecture = "x64"
    #endif

    static func bundledURL() -> URL? {
        resolve(in: Bundle.main.bundleURL, architecture: currentArchitecture)
    }

    static func bundledBunURL() -> URL? {
        resolveBun(in: Bundle.main.bundleURL, architecture: currentArchitecture)
    }

    static func authenticationFileURL(
        applicationSupportDirectory: URL
    ) -> URL {
        agentDirectoryURL(applicationSupportDirectory: applicationSupportDirectory)
            .appendingPathComponent("auth.json", isDirectory: false)
    }

    static func agentDirectoryURL(
        applicationSupportDirectory: URL
    ) -> URL {
        applicationSupportDirectory
            .appendingPathComponent("pi-work", isDirectory: true)
            .appendingPathComponent("Agent", isDirectory: true)
    }

    static func resolve(
        in appBundleURL: URL,
        architecture: String,
        fileManager: FileManager = .default
    ) -> URL? {
        let candidate = appBundleURL.appendingPathComponent(
            "Contents/Helpers/AgentHost/\(architecture)/\(filename)",
            isDirectory: false
        )
        return fileManager.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }

    static func resolveBun(
        in appBundleURL: URL,
        architecture: String,
        fileManager: FileManager = .default
    ) -> URL? {
        let candidate = appBundleURL.appendingPathComponent(
            "Contents/Helpers/Bun/\(architecture)/\(bunFilename)",
            isDirectory: false
        )
        return fileManager.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }
}
