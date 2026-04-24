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
        guard orchestrator == nil else { return }

        let outputDirectory = storageDirectory
            .agentMemoryDirectory()
            .appendingPathComponent("raw", isDirectory: true)
        print("📁 [OCR] 输出目录: \(outputDirectory.path)")

        let instance = OCRCaptureOrchestrator(outputDirectory: outputDirectory)

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
