import AVFoundation
import Foundation
import Observation
import Speech

/// On-device speech-to-text for the inspector's voice notes (gloves on, hands
/// dirty). Wraps `SFSpeechRecognizer` + `AVAudioEngine`. It is honest about
/// availability: if the microphone or permission is missing it surfaces a
/// friendly message instead of faking input.
@Observable
@MainActor
final class SpeechDictationService {
    enum State: Equatable {
        case idle
        case listening
        case unavailable(String)
    }

    private(set) var state: State = .idle
    /// Live partial transcript while listening; the final value persists until
    /// the next `start()`.
    private(set) var transcript: String = ""

    private let recognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    var isListening: Bool {
        if case .listening = state { return true }
        return false
    }

    /// Toggle dictation on/off — bound to the voice-note button.
    func toggle() {
        if isListening {
            stop()
        } else {
            Task { await start() }
        }
    }

    func start() async {
        guard !isListening else { return }
        transcript = ""

        let speechStatus = await Self.requestSpeechAuthorization()
        guard speechStatus == .authorized else {
            state = .unavailable("Allow Speech Recognition in Settings to dictate notes.")
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            state = .unavailable("Speech recognition isn’t available right now.")
            return
        }

        do {
            try startEngine(with: recognizer)
            state = .listening
        } catch {
            state = .unavailable("Couldn’t start the microphone.")
        }
    }

    func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        if case .listening = state { state = .idle }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startEngine(with recognizer: SFSpeechRecognizer) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil || (result?.isFinal ?? false) {
                    self.stop()
                }
            }
        }
    }

    private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}
