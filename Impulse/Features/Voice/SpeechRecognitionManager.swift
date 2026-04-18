import AVFoundation
import Combine
import Speech
import SwiftUI

@MainActor
final class SpeechRecognitionManager: ObservableObject {
    @Published var isListening = false
    @Published var transcript = ""
    @Published var errorMessage: String?

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-Hans"))
        ?? SFSpeechRecognizer()

    private var textBeforeListening = ""

    func startListening(currentText: String) {
        guard !isListening else { return }

        textBeforeListening = currentText
        transcript = ""
        errorMessage = nil

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch status {
                case .authorized:
                    self.beginRecording()
                case .denied:
                    self.errorMessage = "语音识别权限被拒绝，请在系统设置中开启"
                case .restricted:
                    self.errorMessage = "此设备不支持语音识别"
                case .notDetermined:
                    self.errorMessage = "语音识别权限未确定"
                @unknown default:
                    self.errorMessage = "语音识别不可用"
                }
            }
        }
    }

    func stopListening() {
        guard isListening else { return }

        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        audioEngine = nil
        isListening = false
    }

    var composedText: String {
        let trimmedBefore = textBeforeListening.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBefore.isEmpty {
            return trimmedTranscript
        }
        if trimmedTranscript.isEmpty {
            return trimmedBefore
        }
        return trimmedBefore + " " + trimmedTranscript
    }

    private func beginRecording() {
        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            errorMessage = "语音识别服务不可用"
            return
        }

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            errorMessage = "麦克风格式无效，请检查音频输入设备"
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            errorMessage = "无法启动音频引擎：\(error.localizedDescription)"
            return
        }

        self.audioEngine = engine
        self.recognitionRequest = request
        self.isListening = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }

                if let error {
                    let nsError = error as NSError
                    // Code 1 = recognition ended normally (user stopped), 216 = request cancelled
                    if nsError.domain == "kAFAssistantErrorDomain" && (nsError.code == 1 || nsError.code == 216) {
                        return
                    }
                    self.errorMessage = "识别出错：\(error.localizedDescription)"
                    self.stopListening()
                }
            }
        }
    }
}
