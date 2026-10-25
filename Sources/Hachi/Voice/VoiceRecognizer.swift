import AVFoundation
import Foundation
import Speech

/// Mengubah suara menjadi teks memakai pengenal suara bawaan Apple (gratis).
/// Utama: `DictationTranscriber` on-device (offline). Cadangan: `SFSpeechRecognizer` lewat server Apple.
@MainActor
final class VoiceRecognizer: ObservableObject {
    enum State: Equatable {
        case idle
        case preparing(String)
        case listening
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    /// Teks sejauh ini (yang sudah pasti + yang masih berubah).
    @Published private(set) var transcript = ""

    private var locale = Locale(identifier: "id_ID")
    private var engine: AVAudioEngine?
    private var finalized = ""
    private var volatile = ""

    // On-device
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var results: Task<Void, Never>?

    // Server Apple
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var serverFinished: CheckedContinuation<Void, Never>?

    var isActive: Bool {
        switch state {
        case .preparing, .listening: true
        default: false
        }
    }

    /// `language`: "id" atau "en". Bahasa Inggris memakai logat wilayah Mac bila tersedia, kalau tidak en_US.
    func start(language: String) async {
        guard !isActive else { return }
        finalized = ""
        volatile = ""
        transcript = ""
        state = .preparing(String(localized: "Getting the microphone ready…"))

        locale = await Self.locale(for: language)
        guard await Self.microphoneAllowed() else {
            state = .failed(String(localized: "Microphone access was denied. Open System Settings → Privacy & Security → Microphone."))
            return
        }
        do {
            try await startOnDevice()
        } catch {
            NSLog("Hachi: suara on-device gagal (\(error)), pakai server Apple")
            stopEngine()
            do {
                try await startServer()
            } catch {
                stopEngine()
                state = .failed(String(localized: "Speech recognition isn't available: \(error.localizedDescription)"))
                return
            }
        }
        if case .preparing = state { state = .listening }
    }

    /// Berhenti merekam lalu mengembalikan teks akhir.
    @discardableResult
    func stop() async -> String {
        guard isActive else { return transcript }
        stopEngine()
        if let analyzer {
            input?.finish()
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
            await results?.value
        } else if let request {
            request.endAudio()
            await withCheckedContinuation { continuation in
                serverFinished = continuation
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    self.finishServerWait()
                }
            }
            recognition?.cancel()
        }
        analyzer = nil
        input = nil
        results = nil
        request = nil
        recognition = nil
        state = .idle
        return transcript.trimmingCharacters(in: .whitespaces)
    }

    func cancel() {
        stopEngine()
        input?.finish()
        results?.cancel()
        recognition?.cancel()
        analyzer = nil
        input = nil
        results = nil
        request = nil
        recognition = nil
        state = .idle
    }

    // MARK: - On-device

    private func startOnDevice() async throws {
        let transcriber = DictationTranscriber(locale: locale, preset: .progressiveShortDictation)
        if let install = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            state = .preparing(String(localized: "Downloading the speech model (one time only)…"))
            try await install.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw VoiceError(String(localized: "Unsupported audio format"))
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        self.analyzer = analyzer
        input = continuation

        results = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    self?.receive(String(result.text.characters), final: result.isFinal)
                }
            } catch {
                NSLog("Hachi: hasil suara berhenti (\(error))")
            }
        }
        try await analyzer.start(inputSequence: stream)

        let engine = AVAudioEngine()
        try Self.installTap(on: engine, convertingTo: format) { buffer in
            continuation.yield(AnalyzerInput(buffer: buffer))
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    // MARK: - Server Apple

    private func startServer() async throws {
        let status = await Self.speechAuthorization()
        guard status == .authorized else {
            throw VoiceError(String(localized: "Speech Recognition access was denied (System Settings → Privacy & Security → Speech Recognition)"))
        }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw VoiceError(String(localized: "an internet connection is needed"))
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        self.request = request

        recognition = Self.recognize(with: recognizer, request: request) { [weak self] text, done in
            Task { @MainActor in
                guard let self else { return }
                if let text {
                    self.finalized = ""
                    self.receive(text, final: false)
                }
                if done { self.finishServerWait() }
            }
        }

        let engine = AVAudioEngine()
        try Self.installTap(on: engine, convertingTo: nil) { buffer in
            request.append(buffer)
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
    }

    private func finishServerWait() {
        serverFinished?.resume()
        serverFinished = nil
    }

    // MARK: - Bersama

    private func receive(_ text: String, final: Bool) {
        if final {
            finalized += text
            volatile = ""
        } else {
            volatile = text
        }
        transcript = (finalized + volatile).trimmingCharacters(in: .whitespaces)
    }

    private func stopEngine() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }

    private static func locale(for language: String) async -> Locale {
        guard language == "en" else { return Locale(identifier: "id_ID") }
        let regional = Locale(identifier: "en_" + (Locale.current.region?.identifier ?? "US"))
        return await DictationTranscriber.supportedLocale(equivalentTo: regional) ?? Locale(identifier: "en_US")
    }

    private static func microphoneAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    private nonisolated static func speechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }

    /// Hasil dikirim dari thread lain, jadi closure-nya dibuat di luar main actor.
    private nonisolated static func recognize(
        with recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        handler: @escaping @Sendable (String?, Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            handler(result?.bestTranscription.formattedString, (result?.isFinal ?? false) || error != nil)
        }
    }

    /// Dipanggil di luar main actor: tap mikrofon berjalan di thread audio.
    private nonisolated static func installTap(
        on engine: AVAudioEngine,
        convertingTo target: AVAudioFormat?,
        deliver: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) throws {
        let node = engine.inputNode
        let source = node.outputFormat(forBus: 0)
        guard source.sampleRate > 0 else { throw VoiceError(String(localized: "No microphone found")) }
        let converter = target.flatMap { $0 == source ? nil : AVAudioConverter(from: source, to: $0) }

        node.installTap(onBus: 0, bufferSize: 4096, format: source) { buffer, _ in
            guard let converter, let target else {
                deliver(buffer)
                return
            }
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / source.sampleRate) + 1
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var consumed = false
            var error: NSError?
            converter.convert(to: output, error: &error) { _, status in
                if consumed {
                    status.pointee = .noDataNow
                    return nil
                }
                consumed = true
                status.pointee = .haveData
                return buffer
            }
            if error == nil, output.frameLength > 0 { deliver(output) }
        }
    }
}

struct VoiceError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
