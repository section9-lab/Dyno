import Foundation
import os.log

/// Thin wrapper over `os.Logger` for the whole app. Use the per-domain
/// loggers (`AppLog.persistence`, `AppLog.agent`, etc.) so the macOS Console
/// can filter by `subsystem` + `category`.
///
/// We deliberately wrap `Logger` (instead of letting callers `import os.log`
/// directly) so we can:
///   - Add a single throttle/buffering layer in the future
///   - Pipe to an in-app developer console
///   - Decide later whether to forward to a remote sink
///
/// CALL CONVENTIONS:
///   - `error` for things that the user might notice or that lose data.
///   - `notice` for state changes worth seeing in the Console (legacy data
///     migrations, fresh provider discovery, etc.).
///   - `debug` for fine-grained tracing — stripped from release builds.
enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.section9lab.PiWork"

    static let agent = Logger(subsystem: subsystem, category: "agent")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let sandbox = Logger(subsystem: subsystem, category: "sandbox")
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let app = Logger(subsystem: subsystem, category: "app")
}
