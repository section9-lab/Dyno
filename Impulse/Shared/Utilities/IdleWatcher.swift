import Cocoa

@MainActor
final class IdleWatcher {
    private var timer: Timer?
    private var lastTriggerTime: TimeInterval = 0
    private var lastForcedTriggerTime: Date = Date()
    private var isIdle = false

    var threshold: TimeInterval = 5.0 // 默认 5 秒进入空闲
    var periodicInterval: TimeInterval = 30.0 // 空闲期间每 30 秒触发一次
    var forcedInterval: TimeInterval = 600.0 // 即使在活动，每 10 分钟也强制触发一次
    
    var onIdle: (() -> Void)?

    func start() {
        stop()
        print("⏳ [Idle] 启动监控 (阈值: \(threshold)s, 周期: \(periodicInterval)s, 强制: \(forcedInterval)s)")
        lastForcedTriggerTime = Date()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            // Timer fires on the main run loop; hop to the main actor so we
            // can touch the `@MainActor`-isolated state safely.
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        let idleTime = Self.getIdleTime()
        let now = Date()

        // 检查是否达到强制触发间隔（无论是否空闲）
        if now.timeIntervalSince(lastForcedTriggerTime) >= forcedInterval {
            print("⏳ [Idle] 达到强制采样时间点，执行捕获")
            lastForcedTriggerTime = now
            trigger()
            return
        }

        if idleTime >= threshold {
            if !isIdle {
                print("⏳ [Idle] 检测到空闲 (\(Int(idleTime))s)")
                isIdle = true
                trigger()
            } else {
                if idleTime - lastTriggerTime >= periodicInterval {
                    print("⏳ [Idle] 持续空闲中，执行周期性采样 (\(Int(idleTime))s)")
                    trigger()
                }
            }
        } else {
            if isIdle {
                print("⏳ [Idle] 退出空闲状态")
            }
            isIdle = false
            lastTriggerTime = 0
        }
    }

    private func trigger() {
        lastTriggerTime = Self.getIdleTime()
        onIdle?()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isIdle = false
        lastTriggerTime = 0
    }

    nonisolated static func getIdleTime() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null)
    }
}
