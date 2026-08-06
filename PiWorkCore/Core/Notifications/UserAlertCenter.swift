import Foundation
import SwiftUI

@MainActor
public final class UserAlertCenter: ObservableObject {
    public static let shared = UserAlertCenter()

    @Published public private(set) var current: UserAlert?

    private var queue: [UserAlert] = []
    private var recentlyPosted: [String: Date] = [:]
    private var autoDismissTask: Task<Void, Never>?

    public let dedupeWindow: TimeInterval
    private let now: () -> Date
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

    public func post(_ alert: UserAlert) {
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

    public func dismissCurrent() {
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
        autoDismissTask = scheduleAutoDismissImpl(delay) {
            Task { @MainActor [weak self] in
                self?.dismissCurrent()
            }
        }
    }
}

public struct UserAlert: Equatable {
    public let id: String
    public let severity: Severity
    public let title: String
    public let detail: String?
    public let autoDismissAfter: TimeInterval?

    public enum Severity {
        case error
        case warning
        case info
    }

    public init(id: String, severity: Severity, title: String, detail: String?, autoDismissAfter: TimeInterval?) {
        self.id = id
        self.severity = severity
        self.title = title
        self.detail = detail
        self.autoDismissAfter = autoDismissAfter
    }
}

public extension UserAlert {
    static func persistenceError(id: String, title: String, detail: String? = nil) -> UserAlert {
        UserAlert(id: id, severity: .error, title: title, detail: detail, autoDismissAfter: nil)
    }

    static func warning(id: String, title: String, detail: String? = nil) -> UserAlert {
        UserAlert(id: id, severity: .warning, title: title, detail: detail, autoDismissAfter: 8)
    }

    static func info(id: String, title: String, detail: String? = nil) -> UserAlert {
        UserAlert(id: id, severity: .info, title: title, detail: detail, autoDismissAfter: 4)
    }
}

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
