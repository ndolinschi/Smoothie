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
    /// Most recent buffer's RMS, mapped to 0...1. Drives the composer
    /// waveform animation while listening.
    private(set) var level: Float = 0

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
        #if targetEnvironment(simulator)
        state = .unavailable("Voice input needs a real iPhone — Speech Recognition doesn't run in the iOS Simulator. Pair, build to your device, and try again.")
        return
        #else
        guard recognizer?.isAvailable == true else {
            state = .unavailable("Speech recognition isn't available right now. Check that it's enabled in iOS Settings → Privacy & Security → Speech Recognition.")
            return
        }
        let granted = await Self.requestAuthorization()
        guard granted else {
            state = .unavailable("Grant Microphone + Speech Recognition in iOS Settings → Privacy & Security → Smoothie.")
            return
        }
        #endif

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
                let mapped = Self.rmsLevel(of: buffer)
                Task { @MainActor [weak self] in self?.level = mapped }
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
        level = 0
        state = .idle
    }

    /// Compute the per-buffer RMS amplitude, mapped into 0...1 with a gain that
    /// makes typical speech visibly drive the waveform. Cheap — no allocations.
    private static func rmsLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        let samples = channelData[0]
        var sumOfSquares: Float = 0
        for i in 0..<frames {
            let s = samples[i]
            sumOfSquares += s * s
        }
        let rms = (sumOfSquares / Float(frames)).squareRoot()
        return min(1, rms.squareRoot() * 4)
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
