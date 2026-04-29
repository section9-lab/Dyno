import Cocoa
import ScreenCaptureKit

@MainActor
final class ScreenCaptureService: @unchecked Sendable {

    enum CaptureError: LocalizedError {
        case screenshotFailed
        case permissionDenied

        var errorDescription: String? {
            switch self {
            case .screenshotFailed:
                return "截图失败"
            case .permissionDenied:
                return "需要屏幕录制权限"
            }
        }
    }

    private let permissionManager = ScreenCapturePermissionManager.shared

    func captureScreen(promptIfNeeded: Bool = true) async throws -> NSImage {
        let hasPermission = permissionManager.ensurePermissionForCapture(promptIfNeeded: promptIfNeeded)

        guard hasPermission else {
            throw CaptureError.permissionDenied
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

            guard let display = content.displays.first else {
                throw CaptureError.screenshotFailed
            }

            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height

            let filter = SCContentFilter(display: display, excludingWindows: [])

            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

            await MainActor.run {
                permissionManager.updatePermissionState(granted: true)
            }

            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } catch {
            if isLikelyPermissionError(error) {
                await MainActor.run {
                    permissionManager.updatePermissionState(granted: false)
                }
                throw CaptureError.permissionDenied
            }
            throw error
        }
    }

    func captureScreenToURL(_ url: URL, promptIfNeeded: Bool = true) async throws -> URL {
        let image = try await captureScreen(promptIfNeeded: promptIfNeeded)
        return try write(image, to: url)
    }

    func write(_ image: NSImage, to url: URL) throws -> URL {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw CaptureError.screenshotFailed
        }

        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try pngData.write(to: url)
        return url
    }

    private func isLikelyPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError

        if nsError.domain.contains("SCStreamError") {
            return true
        }

        let message = nsError.localizedDescription.lowercased()
        return message.contains("not authorized") ||
               message.contains("permission") ||
               message.contains("screen recording") ||
               message.contains("未授权") ||
               message.contains("权限")
    }
}
