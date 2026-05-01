import Foundation
import SwiftUI

/// User-facing notification channel. Distinct from `AppLog` (which is for
/// developers) — `UserAlertCenter` is for things the *user* should know about,
/// rendered as a non-modal banner inside `ContentView`.
///
/// Posting rules:
///   - One banner visible at a time. New alerts queue up.
///   - Same `id` within `dedupeWindow` is dropped (prevents alert spam when a
///     failing operation is retried in a tight loop).
///   - User can dismiss; banners may also auto-dismiss after `autoDismissAfter`
///     (nil = stay until user closes).
///
/// Threading: `@MainActor` because consumers are SwiftUI views.
///
/// Testability: `dedupeWindow` and `now` (clock) are injectable. Production
/// uses the static `.shared` singleton; tests build their own instance with
/// a controllable clock.
@MainActor
final class UserAlertCenter: ObservableObject {
    static let shared = UserAlertCenter()

    @Published private(set) var current: UserAlert?

    private var queue: [UserAlert] = []
    private var recentlyPosted: [String: Date] = [:]
    private var autoDismissTask: Task<Void, Never>?

    let dedupeWindow: TimeInterval
    private let now: () -> Date
    /// Schedules an auto-dismiss. Default uses `Task.sleep` on real time;
    /// tests can pass a synchronous (or no-op) scheduler.
    /// Marked `@Sendable` so Swift 6 strict-concurrency lets us spawn a Task
    /// from inside the default implementation without complaining about the
    /// captured `action` closure crossing actor boundaries.
    private let scheduleAutoDismissImpl: @Sendable (TimeInterval, @escaping @Sendable () -> Void) -> Task<Void, Never>

    init(
        dedupeWindow: TimeInterval = 5,
        now: @escaping () -> Date = Date.init,
        scheduleAutoDismiss: @escaping @Sendable (TimeInterval, @escaping @Sendable () -> Void) -> Task<Void, Never> = userAlertCenterDefaultScheduler
    ) {
        self.dedupeWindow = dedupeWindow
        self.now = now
        self.scheduleAutoDismissImpl = scheduleAutoDismiss
    }

    /// Post an alert. Returns immediately; the banner appears the next runloop
    /// turn (or queues if one is already showing).
    func post(_ alert: UserAlert) {
        let timestamp = now()
        if let lastSeen = recentlyPosted[alert.id],
           timestamp.timeIntervalSince(lastSeen) < dedupeWindow {
            return
        }
        recentlyPosted[alert.id] = timestamp

        if current == nil {
            current = alert
            scheduleAutoDismiss(for: alert)
        } else {
            queue.append(alert)
        }
    }

    /// Dismiss the currently-displayed alert and advance to the next queued one.
    func dismissCurrent() {
        autoDismissTask?.cancel()
        autoDismissTask = nil

        if !queue.isEmpty {
            let next = queue.removeFirst()
            current = next
            scheduleAutoDismiss(for: next)
        } else {
            current = nil
        }
    }

    private func scheduleAutoDismiss(for alert: UserAlert) {
        guard let delay = alert.autoDismissAfter else { return }
        // `weak self` keeps this @Sendable — the closure captures only an
        // optional weak reference, no main-actor state crosses the boundary.
        autoDismissTask = scheduleAutoDismissImpl(delay) { [weak self] in
            Task { @MainActor in
                self?.dismissCurrent()
            }
        }
    }
}

/// A single notification rendered as a banner.
struct UserAlert: Equatable {
    /// Stable identifier used for dedupe. Reuse the same id for the same
    /// underlying problem (e.g. "persist.projects.failed") so retries within
    /// the dedupe window don't stack up.
    let id: String
    let severity: Severity
    /// The localized title shown in the banner. Caller is responsible for
    /// passing already-localized text (use `L10n.tr(...)`).
    let title: String
    let detail: String?
    /// Auto-dismiss after this many seconds. `nil` = stay until user dismisses.
    let autoDismissAfter: TimeInterval?

    enum Severity {
        case error
        case warning
        case info
    }
}

// MARK: - Convenience constructors

extension UserAlert {
    /// Persistence error — defaults to staying until user dismisses (data
    /// loss is important enough to require acknowledgement).
    static func persistenceError(id: String, title: String, detail: String? = nil) -> UserAlert {
        UserAlert(id: id, severity: .error, title: title, detail: detail, autoDismissAfter: nil)
    }

    /// Recoverable warning — auto-dismisses after 8 seconds.
    static func warning(id: String, title: String, detail: String? = nil) -> UserAlert {
        UserAlert(id: id, severity: .warning, title: title, detail: detail, autoDismissAfter: 8)
    }

    /// Transient info (e.g. "Backup created") — auto-dismisses after 4 seconds.
    static func info(id: String, title: String, detail: String? = nil) -> UserAlert {
        UserAlert(id: id, severity: .info, title: title, detail: detail, autoDismissAfter: 4)
    }
}

/// Default real-time scheduler. Free function (not a method) so it lives
/// outside `UserAlertCenter`'s `@MainActor` isolation — otherwise Swift 6
/// strict concurrency refuses to use it as a `@Sendable` default argument.
@Sendable
private func userAlertCenterDefaultScheduler(
    delay: TimeInterval,
    action: @escaping @Sendable () -> Void
) -> Task<Void, Never> {
    Task {
        try? await Task.sleep(for: .seconds(delay))
        guard !Task.isCancelled else { return }
        action()
    }
}
