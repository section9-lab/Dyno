import AVFoundation
import Combine
import Speech
import SwiftUI

@MainActor
final class SpeechRecognitionManager: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var isRewriting = false
    @Published var transcript = ""
    @Published var errorMessage: String?

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var didInstallTap = false
    private var state: ListeningState = .idle {
        didSet {
            isListening = state.isCaptureActive
        }
    }

    private var textBeforeListening = ""

    func startListening(currentText: String) {
        guard state.isIdle else { return }

        let sessionID = UUID()
        state = .requestingAuthorization(sessionID)
        textBeforeListening = currentText
        transcript = ""
        errorMessage = nil
        isRewriting = false

        VoiceInputAuthorization.request { [weak self] status in
            guard let self else { return }
            guard self.state.matches(sessionID) else { return }

            switch status {
            case .authorized:
                self.beginRecording(sessionID: sessionID)
            case .microphoneDenied, .speechDenied:
                self.finishWithError(L10n.tr("voice.error.denied"))
            case .speechRestricted:
                self.finishWithError(L10n.tr("voice.error.restricted"))
            case .speechNotDetermined:
                self.finishWithError(L10n.tr("voice.error.not_determined"))
            case .unavailable:
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
        guard state.matches(sessionID) else { return }
        guard let recognizer = makeSpeechRecognizer(), recognizer.isAvailable else {
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

    private func makeSpeechRecognizer() -> SFSpeechRecognizer? {
        let language = LocalizationManager.shared.language
        let locale = Locale(identifier: language.speechLocaleIdentifier)
        guard SFSpeechRecognizer.supportedLocales().contains(locale) else {
            return nil
        }
        return SFSpeechRecognizer(locale: locale)
    }

    private func handleRecognition(transcript: String?, isFinal: Bool, error: NSError?) {
        if let transcript {
            self.transcript = transcript
        }

        if let error {
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
        recognitionTask?.cancel()
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

private enum VoiceInputAuthorization {
    enum Status {
        case authorized
        case microphoneDenied
        case speechDenied
        case speechRestricted
        case speechNotDetermined
        case unavailable
    }

    static func request(_ completion: @escaping @MainActor (Status) -> Void) {
        requestMicrophone { microphoneAllowed in
            guard microphoneAllowed else {
                Task { @MainActor in
                    completion(.microphoneDenied)
                }
                return
            }

            SFSpeechRecognizer.requestAuthorization { status in
                let mappedStatus: Status
                switch status {
                case .authorized:
                    mappedStatus = .authorized
                case .denied:
                    mappedStatus = .speechDenied
                case .restricted:
                    mappedStatus = .speechRestricted
                case .notDetermined:
                    mappedStatus = .speechNotDetermined
                @unknown default:
                    mappedStatus = .unavailable
                }

                Task { @MainActor in
                    completion(mappedStatus)
                }
            }
        }
    }

    private static func requestMicrophone(_ completion: @escaping @Sendable (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
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

    var isCaptureActive: Bool {
        switch self {
        case .requestingAuthorization, .starting, .recording:
            return true
        case .idle:
            return false
        }
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
