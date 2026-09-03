import AVFoundation
import Foundation
import Observation
import Speech
import UIKit

/// On-device speech-to-text for the inspector's voice notes (gloves on, hands
/// dirty). Wraps `SFSpeechRecognizer` + `AVAudioEngine`. It is honest about
/// availability: if the microphone or permission is missing it surfaces a
/// friendly message instead of faking input.
///
/// AVAudioEngine `installTap` aborts the process (not a Swift `Error`) if a tap
/// is already on the bus. We track installation ourselves and always tear down
/// before a new start so a failed first attempt cannot crash the next tap.
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
    private var isTapInstalled = false
    private var isStarting = false

    /// Prepared generators so start/stop taps feel instant on-device.
    private let startImpact = UIImpactFeedbackGenerator(style: .medium)
    private let stopImpact = UIImpactFeedbackGenerator(style: .rigid)
    private let warnNotify = UINotificationFeedbackGenerator()

    var isListening: Bool {
        if case .listening = state { return true }
        return false
    }

    /// Toggle dictation on/off — bound to the voice-note button.
    func toggle() {
        startImpact.prepare()
        stopImpact.prepare()
        warnNotify.prepare()
        if isListening {
            stop(haptic: true)
        } else if !isStarting {
            Task { await start() }
        }
    }

    func start() async {
        guard !isListening, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }

        teardownEngine()
        transcript = ""

        let speechStatus = await Self.requestSpeechAuthorization()
        guard speechStatus == .authorized else {
            failUnavailable("Allow Speech Recognition in Settings to dictate notes.")
            return
        }

        let micStatus = await Self.requestMicrophoneAuthorization()
        guard micStatus else {
            failUnavailable("Allow Microphone access in Settings to dictate notes.")
            return
        }

        guard let recognizer, recognizer.isAvailable else {
            failUnavailable("Speech recognition isn’t available right now.")
            return
        }

        do {
            try startEngine(with: recognizer)
            state = .listening
            startImpact.impactOccurred(intensity: 1.0)
        } catch {
            teardownEngine()
            failUnavailable("Couldn’t start the microphone. Check Settings → Privacy → Microphone.")
        }
    }

    func stop() {
        stop(haptic: false)
    }

    /// - Parameter haptic: `true` when the user intentionally stops dictation
    ///   (button toggle). Silent when the recognizer ends on its own or the
    ///   view disappears, so background teardown doesn’t buzz the phone.
    private func stop(haptic: Bool) {
        let wasListening = isListening
        teardownEngine()
        if case .listening = state { state = .idle }
        if haptic, wasListening {
            stopImpact.impactOccurred(intensity: 0.9)
        }
    }

    private func failUnavailable(_ message: String) {
        state = .unavailable(message)
        warnNotify.notificationOccurred(.warning)
    }

    private func teardownEngine() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startEngine(with recognizer: SFSpeechRecognizer) throws {
        teardownEngine()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw SpeechEngineError.invalidInputFormat
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        isTapInstalled = true

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

    private static func requestMicrophoneAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

private enum SpeechEngineError: Error {
    case invalidInputFormat
}
