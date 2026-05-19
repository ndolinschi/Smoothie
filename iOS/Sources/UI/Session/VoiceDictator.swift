import AVFoundation
import Speech
import SwiftUI

/// Minimal Speech-framework dictation helper. Press the mic button to start;
/// transcription is appended to the bound text field; press again to stop.
/// On-device speech recognition is preferred when available (privacy +
/// faster); otherwise the system falls back to Apple-cloud recognition.
@MainActor
@Observable
final class VoiceDictator {
    enum State {
        case idle
        case listening
        case unavailable(String)
    }

    private(set) var state: State = .idle
    private(set) var draft: String = ""

    private let recognizer: SFSpeechRecognizer?
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    init(locale: Locale = .current) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
    }

    var isListening: Bool {
        if case .listening = state { return true }
        return false
    }

    func start(initial: String, onChunk: @escaping (String) -> Void) async {
        guard recognizer?.isAvailable == true else {
            state = .unavailable("Speech recognition isn't available right now.")
            return
        }
        let granted = await Self.requestAuthorization()
        guard granted else {
            state = .unavailable("Grant Microphone + Speech Recognition in iOS Settings.")
            return
        }

        do {
            try setupAudioSession()
            request = SFSpeechAudioBufferRecognitionRequest()
            request?.shouldReportPartialResults = true
            if let recognizer, recognizer.supportsOnDeviceRecognition {
                request?.requiresOnDeviceRecognition = true
            }

            draft = initial
            let baseLength = initial.count

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
            state = .listening

            guard let recognizer, let request else { return }
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    let transcript = result.bestTranscription.formattedString
                    Task { @MainActor in
                        let prefix = initial.isEmpty ? "" : (initial.hasSuffix(" ") ? initial : initial + " ")
                        self.draft = prefix + transcript
                        onChunk(self.draft)
                    }
                }
                if error != nil || result?.isFinal == true {
                    Task { @MainActor in self.stop() }
                }
                _ = baseLength
            }
        } catch {
            state = .unavailable("Couldn't start the microphone: \(error.localizedDescription)")
        }
    }

    func stop() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        state = .idle
    }

    private func setupAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private static func requestAuthorization() async -> Bool {
        let speechOK = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        guard speechOK else { return false }
        let micOK = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        return micOK
    }
}
