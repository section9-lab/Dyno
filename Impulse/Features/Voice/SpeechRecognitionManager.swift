import AVFoundation
import Combine
import Speech
import SwiftUI

@MainActor
final class SpeechRecognitionManager: ObservableObject {
    @Published private(set) var isListening = false
    @Published var transcript = ""
    @Published var errorMessage: String?

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var didInstallTap = false
    private var state: ListeningState = .idle {
        didSet {
            isListening = state.isRecording
        }
    }
    private var speechRecognizer: SFSpeechRecognizer? {
        let language = LocalizationManager.shared.language
        return SFSpeechRecognizer(locale: Locale(identifier: language.speechLocaleIdentifier))
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
            ?? SFSpeechRecognizer()
    }

    private var textBeforeListening = ""

    func startListening(currentText: String) {
        guard state.isIdle else { return }

        let sessionID = UUID()
        state = .requestingAuthorization(sessionID)
        textBeforeListening = currentText
        transcript = ""
        errorMessage = nil

        SpeechAuthorization.request { [weak self] status in
            guard let self else { return }
            guard self.state.matches(sessionID) else { return }

            switch status {
            case .authorized:
                self.beginRecording(sessionID: sessionID)
            case .denied:
                self.finishWithError(L10n.tr("voice.error.denied"))
            case .restricted:
                self.finishWithError(L10n.tr("voice.error.restricted"))
            case .notDetermined:
                self.finishWithError(L10n.tr("voice.error.not_determined"))
            @unknown default:
                self.finishWithError(L10n.tr("voice.error.unavailable"))
            }
        }
    }

    func stopListening() {
        switch state {
        case .idle:
            return
        case .requestingAuthorization:
            state = .idle
        case .starting, .recording:
            finishRecording()
        }
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

    private func beginRecording(sessionID: UUID) {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            finishWithError(L10n.tr("voice.error.service_unavailable"))
            return
        }

        state = .starting(sessionID)

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            finishWithError(L10n.tr("voice.error.invalid_microphone"))
            return
        }

        AudioInputTap.install(on: inputNode, format: recordingFormat, request: request)
        didInstallTap = true

        engine.prepare()
        do {
            try engine.start()
        } catch {
            removeTapIfNeeded(from: inputNode)
            finishWithError(L10n.tr("voice.error.audio_engine", error.localizedDescription))
            return
        }

        audioEngine = engine
        recognitionRequest = request
        recognitionTask = SpeechRecognitionTaskFactory.start(recognizer: recognizer, request: request) { [weak self] transcript, isFinal, error in
            guard let self, self.state.matches(sessionID) else { return }
            self.handleRecognition(transcript: transcript, isFinal: isFinal, error: error)
        }

        state = .recording(sessionID)
    }

    private func handleRecognition(transcript: String?, isFinal: Bool, error: NSError?) {
        if let transcript {
            self.transcript = transcript
        }

        if let error {
            // Code 1 = recognition ended normally (user stopped), 216 = request cancelled
            if error.domain == "kAFAssistantErrorDomain" && (error.code == 1 || error.code == 216) {
                return
            }
            finishWithError(L10n.tr("voice.error.recognition", error.localizedDescription))
        } else if isFinal {
            finishRecording()
        }
    }

    private func finishRecording() {
        let engine = audioEngine
        let request = recognitionRequest

        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil

        engine?.stop()
        if let inputNode = engine?.inputNode {
            removeTapIfNeeded(from: inputNode)
        }
        request?.endAudio()
        state = .idle
    }

    private func finishWithError(_ message: String) {
        errorMessage = message
        finishRecording()
    }

    private func removeTapIfNeeded(from inputNode: AVAudioInputNode) {
        guard didInstallTap else { return }
        didInstallTap = false
        inputNode.removeTap(onBus: 0)
    }
}

private enum SpeechAuthorization {
    static func request(
        _ completion: @escaping @MainActor (SFSpeechRecognizerAuthorizationStatus) -> Void
    ) {
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                completion(status)
            }
        }
    }
}

private enum AudioInputTap {
    static func install(
        on inputNode: AVAudioInputNode,
        format: AVAudioFormat,
        request: SFSpeechAudioBufferRecognitionRequest
    ) {
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }
}

private enum SpeechRecognitionTaskFactory {
    static func start(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        onResult: @escaping @MainActor (String?, Bool, NSError?) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal == true
            let nsError = error.map { $0 as NSError }

            Task { @MainActor in
                onResult(transcript, isFinal, nsError)
            }
        }
    }
}

private enum ListeningState {
    case idle
    case requestingAuthorization(UUID)
    case starting(UUID)
    case recording(UUID)

    var isIdle: Bool {
        if case .idle = self {
            return true
        }
        return false
    }

    var isRecording: Bool {
        if case .recording = self {
            return true
        }
        return false
    }

    func matches(_ sessionID: UUID) -> Bool {
        switch self {
        case .idle:
            return false
        case .requestingAuthorization(let activeSessionID),
             .starting(let activeSessionID),
             .recording(let activeSessionID):
            return activeSessionID == sessionID
        }
    }
}
