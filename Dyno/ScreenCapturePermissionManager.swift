import Foundation
import Combine
import ScreenCaptureKit
import CoreGraphics

@MainActor
final class ScreenCapturePermissionManager: ObservableObject {
    static let shared = ScreenCapturePermissionManager()

    @Published private(set) var isGranted: Bool?
    
    private var isChecking = false
    private var lastCheckTime: Date?
    private var hasRequestedThisLaunch = false

    private init() {}

    func checkPermissionIfNeeded() {
        // Only check if we haven't checked or if last check was more than 5 seconds ago
        if let last = lastCheckTime, Date().timeIntervalSince(last) < 5.0 {
            return
        }
        
        guard !isChecking else { return }
        checkPermission()
    }

    func checkPermission() {
        isChecking = true
        defer {
            isChecking = false
            lastCheckTime = Date()
        }

        // 仅做静默检查，避免在后台轮询时触发不稳定的请求行为。
        let granted = CGPreflightScreenCaptureAccess()
        print("📸 [Permission] Preflight Check: \(granted)")
        isGranted = granted
    }

    @discardableResult
    func ensurePermissionForCapture() -> Bool {
        // 每次触发截图时都先静默检查一次。
        checkPermission()
        if isGranted == true {
            return true
        }

        // 本次启动只主动请求一次，避免后台周期任务反复弹系统提示。
        guard !hasRequestedThisLaunch else {
            print("📸 [Permission] Already requested in this launch, skip prompting")
            return false
        }

        hasRequestedThisLaunch = true
        let granted = CGRequestScreenCaptureAccess()
        print("📸 [Permission] On-demand request: \(granted)")
        isGranted = granted
        lastCheckTime = Date()
        return granted
    }

    func requestPermission() {
        _ = ensurePermissionForCapture()
    }

    func updatePermissionState(granted: Bool) {
        isGranted = granted
        lastCheckTime = Date()
    }

    func resetCache() {
        isGranted = nil
        lastCheckTime = nil
        hasRequestedThisLaunch = false
    }
}
