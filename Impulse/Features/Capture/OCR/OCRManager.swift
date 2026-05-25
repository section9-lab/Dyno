import Foundation
import AppKit
import Combine

@MainActor
final class OCRManager: ObservableObject, @unchecked Sendable {

    static let shared = OCRManager()

    private var orchestrator: OCRCaptureOrchestrator?

    @Published var lastCapturedURL: URL?
    @Published var lastCapturedText: String?

    func start(storageDirectory: URL) {
        guard GeneralSettingsStore.loadOCREnabled() else {
            stop()
            return
        }
        guard orchestrator == nil else { return }

        let rawDirectory = storageDirectory
            .agentMemoryDirectory()
            .appendingPathComponent("raw", isDirectory: true)
        let screenshotDirectory = rawDirectory
            .appendingPathComponent("ocr-screenshots", isDirectory: true)
        let markdownDirectory = rawDirectory
            .appendingPathComponent("ocr-md", isDirectory: true)

        print("📁 [OCR] 截屏目录: \(screenshotDirectory.path)")
        print("📁 [OCR] 文本目录: \(markdownDirectory.path)")

        let instance = OCRCaptureOrchestrator(
            screenshotDirectory: screenshotDirectory,
            markdownDirectory: markdownDirectory
        )

        instance.onStatusChanged = { [weak self] status in
            switch status {
            case .completed(let url):
                self?.lastCapturedURL = url
            default:
                break
            }
        }

        instance.onOCRCompleted = { [weak self] text, url in
            self?.lastCapturedText = text
            self?.lastCapturedURL = url
        }

        orchestrator = instance
        instance.start()
    }

    func stop() {
        orchestrator?.stop()
        orchestrator = nil
    }
}
