import Foundation
import Speech
import AVFoundation
import OSLog

public struct SpeechResult {
    public let text: String
    public let detectedLocale: String
    public let isFinal: Bool
    public let confidence: Float
}

public enum SpeechEngineError: Error, LocalizedError {
    case microphoneNotAuthorized
    case speechNotAuthorized
    case recognizerUnavailable
    case audioSessionFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .microphoneNotAuthorized:   return "Permissão de microfone negada. Vá em System Settings → Privacy → Microphone."
        case .speechNotAuthorized:       return "Permissão de reconhecimento de fala negada."
        case .recognizerUnavailable:     return "Nenhum reconhecedor disponível para o idioma selecionado."
        case .audioSessionFailed(let e): return "Erro de áudio: \(e.localizedDescription)"
        }
    }
}

@MainActor
public class SpeechEngine: NSObject, ObservableObject {
    @Published public var isListening = false

    private var audioEngine = AVAudioEngine()
    private var activePair: LanguagePair?

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var restartPending = false
    private var configObserver: NSObjectProtocol?
    private var watchdogTask: Task<Void, Never>?
    private var lastResultTime: Date = .distantPast

    public var onResult: ((SpeechResult) -> Void)?

    // MARK: - Public

    public func start(pair: LanguagePair) async throws {
        activePair = pair

        let micGranted = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) }
        }
        guard micGranted else { throw SpeechEngineError.microphoneNotAuthorized }

        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else { throw SpeechEngineError.speechNotAuthorized }

        try startSession(pair: pair)
        startWatchdog(pair: pair)
    }

    public func stop() {
        isListening = false
        activePair = nil
        watchdogTask?.cancel(); watchdogTask = nil
        teardown()
    }

    // MARK: - Private

    private func startSession(pair: LanguagePair) throws {
        teardown()

        let localeId = pair.source.id
        ToLangLogger.speech.info("Starting session — locale: \(localeId)")

        guard let rec = SFSpeechRecognizer(locale: Locale(identifier: localeId)),
              rec.isAvailable else {
            throw SpeechEngineError.recognizerUnavailable
        }
        rec.delegate = self
        recognizer = rec
        ToLangLogger.speech.info("Recognizer ready: \(localeId)")

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = false
        req.taskHint = .dictation
        req.addsPunctuation = true
        request = req

        let inputNode = audioEngine.inputNode
        let format = inputNode.inputFormat(forBus: 0)
        ToLangLogger.audio.info("Audio format: \(format.sampleRate)Hz, \(format.channelCount)ch")
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            ToLangLogger.audio.info("Audio config changed — restarting session")
            Task { @MainActor [weak self] in
                guard let self, self.isListening, let pair = self.activePair else { return }
                self.restartPending = false
                self.scheduleRestart(pair: pair, delay: .milliseconds(500))
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            ToLangLogger.audio.info("AVAudioEngine started")
        } catch {
            ToLangLogger.audio.error("AVAudioEngine failed: \(error)")
            throw SpeechEngineError.audioSessionFailed(error)
        }

        task = rec.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in self.handleResult(result, error: error, locale: localeId) }
        }

        lastResultTime = Date()
        isListening = true
    }

    /// Watchdog: if no result arrives within 30s, force-restart the session.
    private func startWatchdog(pair: LanguagePair) {
        watchdogTask?.cancel()
        watchdogTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self, self.isListening else { return }
                let elapsed = Date().timeIntervalSince(self.lastResultTime)
                if elapsed > 30 {
                    ToLangLogger.speech.warning("Watchdog: no result in \(Int(elapsed))s — force restarting")
                    self.restartPending = false
                    self.scheduleRestart(pair: pair, delay: .milliseconds(200))
                }
            }
        }
    }

    private func handleResult(_ result: SFSpeechRecognitionResult?, error: Error?, locale: String) {
        guard isListening else { return }

        if let result {
            let text = result.bestTranscription.formattedString
            let confidence = averageConfidence(result.bestTranscription)
            guard !text.isEmpty else { return }

            lastResultTime = Date()

            if result.isFinal {
                ToLangLogger.speech.info("✅ Final [\(locale)] conf=\(String(format:"%.2f", confidence)): \"\(text)\"")
            } else {
                ToLangLogger.speech.debug("… Partial [\(locale)]: \"\(text)\"")
            }

            onResult?(SpeechResult(text: text, detectedLocale: locale, isFinal: result.isFinal, confidence: confidence))

            if result.isFinal, let pair = activePair {
                scheduleRestart(pair: pair, delay: .milliseconds(300))
            }
        } else if let error {
            let nsErr = error as NSError
            if nsErr.code == 1700 { return } // cancelled — normal
            ToLangLogger.speech.error("Recognition error \(nsErr.code): \(nsErr.localizedDescription)")
            if let pair = activePair {
                let delay: Duration = nsErr.code == 1110 ? .seconds(2) : .seconds(1)
                scheduleRestart(pair: pair, delay: delay)
            }
        }
    }

    private func scheduleRestart(pair: LanguagePair, delay: Duration) {
        guard !restartPending else { return }
        restartPending = true
        Task { @MainActor [weak self] in
            defer { self?.restartPending = false }
            guard let self, self.isListening else { return }
            try? await Task.sleep(for: delay)
            guard self.isListening else { return }
            do {
                try self.startSession(pair: pair)
            } catch {
                ToLangLogger.speech.error("Restart failed: \(error) — retrying in 2s")
                self.restartPending = false
                self.scheduleRestart(pair: pair, delay: .seconds(2))
            }
        }
    }

    private func teardown() {
        restartPending = false
        if let obs = configObserver { NotificationCenter.default.removeObserver(obs); configObserver = nil }
        task?.cancel(); task = nil
        request?.endAudio(); request = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine = AVAudioEngine()
    }

    private func averageConfidence(_ t: SFTranscription) -> Float {
        let segs = t.segments
        guard !segs.isEmpty else { return 0 }
        return segs.map(\.confidence).reduce(0, +) / Float(segs.count)
    }
}

// MARK: - SFSpeechRecognizerDelegate

extension SpeechEngine: SFSpeechRecognizerDelegate {
    nonisolated public func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        ToLangLogger.speech.info("Recognizer availability changed: \(available)")
        guard !available else { return }
        Task { @MainActor [weak self] in
            guard let self, self.isListening, let pair = self.activePair else { return }
            ToLangLogger.speech.warning("Recognizer became unavailable — scheduling restart")
            self.restartPending = false
            self.scheduleRestart(pair: pair, delay: .seconds(2))
        }
    }
}
