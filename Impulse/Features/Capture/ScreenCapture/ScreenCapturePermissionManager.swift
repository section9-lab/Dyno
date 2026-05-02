import Foundation
import AppKit
import Combine
import ScreenCaptureKit
import CoreGraphics

@MainActor
final class ScreenCapturePermissionManager: ObservableObject {
    static let shared = ScreenCapturePermissionManager()

    @Published private(set) var isGranted: Bool?

    private var isProbing = false
    private var lastProbeTime: Date?
    private var didRequestThisLaunch = false
    private var didInstallActivationObserver = false

    private init() {
        installActivationObserver()
    }

    /// Quick, non-authoritative hint. Use only as a fast path; truth comes from `probe()`.
    var preflightHint: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Authoritative permission check. Tries the real ScreenCaptureKit API which is the only
    /// reliable signal — `CGPreflightScreenCaptureAccess` frequently disagrees with the actual
    /// TCC state, especially for Xcode DerivedData builds whose cdhash changes on rebuild.
    @discardableResult
    func probe() async -> Bool {
        if isProbing {
            return isGranted ?? false
        }
        isProbing = true
        defer {
            isProbing = false
            lastProbeTime = Date()
        }

        let granted: Bool
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            granted = true
        } catch {
            granted = false
        }

        let preflight = CGPreflightScreenCaptureAccess()
        print("📸 [Permission] Probe granted=\(granted) preflight=\(preflight)")
        isGranted = granted
        return granted
    }

    func probeIfStale(maxAge: TimeInterval = 5.0) async {
        if let last = lastProbeTime, Date().timeIntervalSince(last) < maxAge {
            return
        }
        _ = await probe()
    }

    /// Trigger the system permission prompt at most once per launch, then probe.
    /// Returns the post-prompt permission state.
    @discardableResult
    func requestPermissionIfNeeded() async -> Bool {
        if await probe() {
            return true
        }

        if !didRequestThisLaunch {
            didRequestThisLaunch = true
            // CGRequestScreenCaptureAccess only shows the system prompt the first time a given
            // binary asks. Subsequent launches (or rebuilt binaries with stale TCC entries)
            // return false silently — that's why we always fall back to the settings deep link.
            let immediate = CGRequestScreenCaptureAccess()
            print("📸 [Permission] CGRequestScreenCaptureAccess immediate=\(immediate)")
        }

        return await probe()
    }

    /// Opens System Settings → Privacy & Security → Screen Recording.
    /// Used as the always-available fallback when TCC silently denies.
    func openSystemSettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    func resetCache() {
        isGranted = nil
        lastProbeTime = nil
        didRequestThisLaunch = false
    }

    // MARK: - App activation re-probe

    private func installActivationObserver() {
        guard !didInstallActivationObserver else { return }
        didInstallActivationObserver = true

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                _ = await self.probe()
            }
        }
    }
}
