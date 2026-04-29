import Foundation
import AppKit

@MainActor
final class OCRCaptureOrchestrator {

    enum Status {
        case idle
        case capturing
        case recognizing
        case saving
        case completed(URL)
        case skipped(reason: String)
        case error(Error)
    }

    private lazy var idleWatcher: IdleWatcher = IdleWatcher()
    private lazy var screenCapture: ScreenCaptureService = ScreenCaptureService()
    private lazy var ocrService: VisionOCRService = VisionOCRService()

    private var screenshotDirectory: URL
    private var markdownDirectory: URL
    private var lastOCRText: String?
    private var lastFingerprint: [UInt8]? // 存储上一次的缩略图指纹

    private var isRunning = false
    private var isProcessing = false

    var onStatusChanged: ((Status) -> Void)?
    var onOCRCompleted: ((String, URL) -> Void)?
    var onError: ((Error) -> Void)?

    init(screenshotDirectory: URL, markdownDirectory: URL) {
        self.screenshotDirectory = screenshotDirectory
        self.markdownDirectory = markdownDirectory
        // 用户停止滑动 2 秒后即视为开始阅读
        idleWatcher.threshold = 2.0
        idleWatcher.periodicInterval = 60.0
        idleWatcher.forcedInterval = 600.0
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        idleWatcher.onIdle = { [weak self] in
            self?.handleIdle()
        }
        idleWatcher.start()
    }

    func stop() {
        idleWatcher.stop()
        isRunning = false
    }

    private func handleIdle() {
        guard !isProcessing else { return }
        isProcessing = true

        Task { @MainActor in
            defer { isProcessing = false }

            do {
                onStatusChanged?(.capturing)
                // 后台 OCR 不应在应用启动后隐式触发系统录屏授权弹窗。
                let image = try await screenCapture.captureScreen(promptIfNeeded: false)
                let timestamp = makeTimestamp()
                let screenshotURL = try saveScreenshot(image, timestamp: timestamp)
                print("📸 [OCR] 原始截屏已保存: \(screenshotURL.path)")

                // --- 视觉指纹检测 ---
                let currentFingerprint = createFingerprint(from: image)
                if let last = lastFingerprint, !isDifferent(last, currentFingerprint) {
                    print("📸 [OCR] 屏幕视觉内容无显著变化，跳过 OCR 提取")
                    onStatusChanged?(.skipped(reason: "内容无变化"))
                    return
                }
                lastFingerprint = currentFingerprint
                // ------------------

                print("📸 [OCR] 检测到画面变化，开始提取文字...")
                onStatusChanged?(.recognizing)

                let text = try await ocrService.recognizeText(from: screenshotURL)
                let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

                guard !trimmedText.isEmpty else {
                    onStatusChanged?(.skipped(reason: "识别结果为空"))
                    return
                }

                // 二次校验：如果图像指纹变了但文字没变（比如只是背景图变了），也跳过
                guard trimmedText != lastOCRText else {
                    onStatusChanged?(.skipped(reason: "文本内容未变化"))
                    return
                }

                lastOCRText = trimmedText
                onStatusChanged?(.saving)

                let activeApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
                let windowTitle = getActiveWindowTitle() ?? "Unknown Window"

                let savedURL = try saveAsMarkdown(
                    text: trimmedText,
                    appName: activeApp,
                    windowTitle: windowTitle,
                    timestamp: timestamp,
                    screenshotURL: screenshotURL
                )
                print("📸 [OCR] 已保存: \(activeApp) - \(windowTitle)")
                onStatusChanged?(.completed(savedURL))

                onOCRCompleted?(trimmedText, savedURL)

            } catch ScreenCaptureService.CaptureError.permissionDenied {
                print("📸 [OCR] 缺少录屏权限，跳过本次 OCR（本次启动不再重复弹窗）")
                onStatusChanged?(.skipped(reason: "缺少录屏权限"))
            } catch {
                print("📸 [OCR] 执行失败: \(error.localizedDescription)")
                onStatusChanged?(.error(error))
                onError?(error)
            }
        }
    }

    // 创建视觉指纹：将图片缩放到 32x32 并提取灰度数据
    private func createFingerprint(from image: NSImage) -> [UInt8] {
        // 使用 Core Graphics 缩放并提取像素
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: [.init(rawValue: "kCGImageSourceShouldCache"): true]) else {
            return []
        }

        // 使用 Core Graphics 缩放并提取像素
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 32,
            height: 32,
            bitsPerComponent: 8,
            bytesPerRow: 32 * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )

        guard let ctx = context else { return [] }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: 32, height: 32))

        guard let data = ctx.data else { return [] }
        let pixelData = data.bindMemory(to: UInt8.self, capacity: 32 * 32 * 4)

        var pixels = [UInt8]()
        // 采样每个像素的亮度 (R+G+B)/3
        for i in 0..<(32 * 32) {
            let offset = i * 4
            let red = pixelData[offset]
            let green = pixelData[offset + 1]
            let blue = pixelData[offset + 2]
            let gray = UInt8((Int(red) + Int(green) + Int(blue)) / 3)
            pixels.append(gray)
        }

        return pixels
    }

    // 比较两个指纹的平均差异
    private func isDifferent(_ old: [UInt8], _ new: [UInt8]) -> Bool {
        guard old.count == new.count, !old.isEmpty else { return true }

        var diffCount = 0
        let threshold: Int = 15 // 灰度差异阈值

        for i in 0..<old.count {
            if abs(Int(old[i]) - Int(new[i])) > threshold {
                diffCount += 1
            }
        }

        // 如果超过 2% 的像素发生了变化，则认为画面不同
        // 这个比例可以过滤掉光标闪烁或菜单栏时间跳动
        let changeRatio = Double(diffCount) / Double(old.count)
        return changeRatio > 0.02
    }

    private func getActiveWindowTitle() -> String? {
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let frontmostAppPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        for window in windowList {
            if let pid = window[kCGWindowOwnerPID as String] as? Int32,
               pid == frontmostAppPID,
               let title = window[kCGWindowName as String] as? String,
               !title.isEmpty {
                return title
            }
        }
        return nil
    }

    private func makeTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
    }

    private func saveScreenshot(_ image: NSImage, timestamp: String) throws -> URL {
        let filename = "ocr-\(timestamp).png"
        let fileURL = screenshotDirectory.appendingPathComponent(filename)
        return try screenCapture.write(image, to: fileURL)
    }

    private func saveAsMarkdown(
        text: String,
        appName: String,
        windowTitle: String,
        timestamp: String,
        screenshotURL: URL
    ) throws -> URL {
        try FileManager.default.createDirectory(at: markdownDirectory, withIntermediateDirectories: true)
        let filename = "ocr-\(timestamp).md"
        let fileURL = markdownDirectory.appendingPathComponent(filename)

        let markdown = """
        # 屏幕捕获记录

        - **时间**: \(Date())
        - **应用**: \(appName)
        - **窗口**: \(windowTitle)
        - **原始截屏**: \(screenshotURL.path)

        ---

        ## 识别内容

        \(text)

        ---
        """
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
