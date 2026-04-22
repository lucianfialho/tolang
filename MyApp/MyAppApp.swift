import AppKit
import SwiftUI
import Speech
import ScreenCaptureKit
import FoundationModels
import OSLog

@main
struct ToLangApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private let menuBar    = MenuBarManager()
    private let llmEngine  = LLMEngine()
    private let overlay    = SubtitleOverlay()
    private var hotkey: HotkeyManager?

    // --- Mic path (YOU speaking) ---
    private let micEngine  = SpeechEngine()

    // --- App audio path (THEM speaking via Discord etc.) ---
    private let appCapture = AppAudioCapture()
    private var appRecognizer: SFSpeechRecognizer?
    private var appRequest: SFSpeechAudioBufferRecognitionRequest?
    private var appTask: SFSpeechRecognitionTask?

    private var translateTask: Task<Void, Never>?
    private var silenceTask:   Task<Void, Never>?   // fires after 1.5s of no new words
    private var contextTask:   Task<Void, Never>?
    private var settingsWindow: NSWindow?
    private var pendingText = ""                     // accumulated transcript waiting to translate

    @AppStorage("selectedPair")
    private var pairData: Data = (try? JSONEncoder().encode(LanguagePair.default)) ?? Data()

    @AppStorage("captureAppBundleID")
    private var captureAppBundleID: String = "com.hnc.Discord"

    private var currentPair: LanguagePair {
        get { (try? JSONDecoder().decode(LanguagePair.self, from: pairData)) ?? .default }
        set { pairData = (try? JSONEncoder().encode(newValue)) ?? pairData }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        )

        menuBar.setup(appName: AppConfig.appName)
        menuBar.onToggleListening  = { [weak self] in self?.toggleListening() }
        menuBar.onPairSelected     = { [weak self] pair in self?.selectPair(pair) }
        menuBar.onSettingsRequested = { [weak self] in self?.openSettings() }

        if trusted {
            hotkey = HotkeyManager(combo: KeyCombo(37, modifiers: [.command, .shift])) { [weak self] in
                self?.toggleListening()
            }
            hotkey?.start()
        }

        // Mic → YOU speaking → translate source→target
        micEngine.onResult = { [weak self] result in
            guard let self else { return }
            self.handleSpeech(result, source: .mic)
        }

        // App audio → THEM speaking → translate target→source
        appCapture.onBuffer = { [weak self] buffer in
            self?.appRequest?.append(buffer)
        }

        Task {
            menuBar.setLoading(message: "Carregando Apple Intelligence…")
            do {
                try await llmEngine.load()
                ToLangLogger.translation.info("✅ LLM ready")
                menuBar.rebuildMenu(activePair: currentPair, isListening: false)
                menuBar.setIdle()
            } catch {
                ToLangLogger.translation.error("❌ LLM failed: \(error)")
                menuBar.setError(message: "Apple Intelligence indisponível: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Controls

    private func openSettings() {
        if let w = settingsWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "ToLang Settings"
        win.contentView = NSHostingView(rootView: ToLangSettingsView())
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = win
    }

    private func selectPair(_ pair: LanguagePair) {
        let was = micEngine.isListening
        if was { stopListening() }
        currentPair = pair
        menuBar.rebuildMenu(activePair: pair, isListening: false)
        if was { startListening() }
    }

    private func toggleListening() {
        micEngine.isListening ? stopListening() : startListening()
    }

    private func startListening() {
        let pair = currentPair
        DispatchQueue.main.async {
            self.overlay.state.isListening    = true
            self.overlay.state.originalText   = ""
            self.overlay.state.translatedText = ""
            self.overlay.state.partialText    = ""
        }
        overlay.showOnScreen()
        menuBar.setListening(pair: pair)
        menuBar.rebuildMenu(activePair: pair, isListening: true)

        // Start context polling
        contextTask = Task {
            while !Task.isCancelled {
                if let ctx = ContextDetector.currentContext() {
                    DispatchQueue.main.async {
                        self.overlay.state.contextLabel = ctx.displayLabel
                        self.overlay.state.contextIcon  = ctx.icon
                    }
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }

        // Start mic (your voice)
        Task {
            do {
                try await micEngine.start(pair: pair)
            } catch {
                menuBar.setError(message: error.localizedDescription)
            }
        }

        // Start app audio (their voice) if a target app is running
        Task { await startAppCapture(pair: pair) }
    }

    private func stopListening() {
        micEngine.stop()
        stopAppCapture()
        contextTask?.cancel(); contextTask = nil
        translateTask?.cancel(); translateTask = nil
        silenceTask?.cancel(); silenceTask = nil
        pendingText = ""
        DispatchQueue.main.async {
            self.overlay.state.isListening  = false
            self.overlay.state.partialText  = ""
            self.overlay.state.contextLabel = ""
        }
        overlay.hide()
        menuBar.setIdle()
        menuBar.rebuildMenu(activePair: currentPair, isListening: false)
    }

    // MARK: - App audio capture (THEM)

    private func startAppCapture(pair: LanguagePair) async {
        let apps = await AppAudioCapture.availableApps()
        guard let target = apps.first(where: { $0.bundleIdentifier == captureAppBundleID })
               ?? AppAudioCapture.knownVoiceApps(from: apps).first
        else { return }

        // Recognizer for their language (target side of pair)
        let theirLocale = pair.bidirectional ? pair.target.id : pair.target.id
        let rec = SFSpeechRecognizer(locale: Locale(identifier: theirLocale))
        appRecognizer = rec

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = false
        req.taskHint = .dictation
        appRequest = req

        appTask = rec?.recognitionTask(with: req) { [weak self] result, error in
            guard let self, let result else { return }
            let text = result.bestTranscription.formattedString
            guard !text.isEmpty else { return }
            let sr = SpeechResult(
                text: text,
                detectedLocale: theirLocale,
                isFinal: result.isFinal,
                confidence: 0.9
            )
            Task { @MainActor in self.handleSpeech(sr, source: .app) }
        }

        do {
            try await appCapture.start(app: target)
            DispatchQueue.main.async {
                self.overlay.state.contextLabel = "🎧 \(target.applicationName)"
                self.overlay.state.contextIcon  = "headphones"
            }
        } catch {
            // App audio not available — mic-only mode, silent fail
        }
    }

    private func stopAppCapture() {
        appTask?.cancel(); appTask = nil
        appRequest?.endAudio(); appRequest = nil
        appCapture.stop()
    }

    // MARK: - Translation

    private enum AudioSource { case mic, app }

    private func handleSpeech(_ result: SpeechResult, source: AudioSource) {
        let icon = source == .mic ? "🎙" : "🎧"
        let text = result.text
        guard !text.isEmpty else { return }

        pendingText = text
        overlay.state.partialText = "\(icon) \(text)"

        silenceTask?.cancel()

        if result.isFinal {
            pendingText = ""
            ToLangLogger.speech.info("Final result — translating: \"\(text)\"")
            Task { @MainActor in
                await self.translate(result: result, source: source)
            }
        } else {
            let wordCount = text.words.count
            if wordCount >= 40 {
                // Long monologue — don't wait for silence, translate now and reset
                pendingText = ""
                ToLangLogger.speech.info("Word limit hit (\(wordCount)) — translating chunk")
                Task { @MainActor in
                    await self.translate(
                        result: SpeechResult(text: text, detectedLocale: result.detectedLocale, isFinal: true, confidence: result.confidence),
                        source: source
                    )
                }
            } else {
                // Short partial: wait 1.5s of silence before translating
                silenceTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(1500))
                    guard !Task.isCancelled, !self.pendingText.isEmpty else { return }
                    let captured = self.pendingText
                    self.pendingText = ""
                    ToLangLogger.speech.info("Silence — translating: \"\(captured)\"")
                    await self.translate(
                        result: SpeechResult(text: captured, detectedLocale: result.detectedLocale, isFinal: true, confidence: result.confidence),
                        source: source
                    )
                }
            }
        }
    }

    private func translate(result: SpeechResult, source: AudioSource) async {
        let pair = currentPair

        // Cap at 60 words — long garbled partials confuse the model and trigger refusals
        let text = result.text.words.suffix(60).joined(separator: " ")
        guard !text.isEmpty else { return }

        let fromFlag = source == .mic ? pair.source.flag : pair.target.flag
        overlay.state.originalText   = "\(fromFlag) \(text)"
        overlay.state.translatedText = ""
        overlay.state.partialText    = ""

        guard llmEngine.isReady else {
            ToLangLogger.translation.warning("LLM not ready — skipping: \"\(text)\"")
            overlay.state.partialText = "⏳ Apple Intelligence carregando…"
            return
        }

        let prompt: String
        let toFlag: String

        if source == .app {
            prompt = "In \(pair.source.name): \(text)"
            toFlag = pair.source.flag
        } else if pair.bidirectional {
            let langA = pair.source.name, langB = pair.target.name
            prompt = "This text is in either \(langA) or \(langB). Output it in the other language:\n\(text)"
            toFlag = "🔄"
        } else {
            prompt = "In \(pair.target.name): \(text)"
            toFlag = pair.target.flag
        }

        ToLangLogger.translation.info("Translating [\(source == .mic ? "mic" : "app")]: \"\(text)\"")

        do {
            let translated = try await llmEngine.run(prompt: prompt)
            ToLangLogger.translation.info("Result: \"\(translated)\"")
            if isModelRefusal(translated) {
                ToLangLogger.translation.warning("Model refusal — showing original: \"\(text)\"")
                overlay.state.translatedText = "\(fromFlag) \(text)"
                overlay.state.partialText    = ""
                return
            }
            let clean = stripPreamble(translated)
            overlay.state.translatedText = "\(toFlag) \(clean)"
            overlay.state.partialText    = ""
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .guardrailViolation:
                // Silently skip — show original text as fallback
                ToLangLogger.translation.warning("Guardrail — showing original: \"\(result.text)\"")
                overlay.state.translatedText = "\(fromFlag) \(result.text)"
                overlay.state.partialText    = ""
            default:
                ToLangLogger.translation.error("Translation failed: \(error)")
                overlay.state.partialText = "⚠️ \(error.localizedDescription)"
            }
        } catch {
            ToLangLogger.translation.error("Translation failed: \(error)")
            overlay.state.partialText = "⚠️ \(error.localizedDescription)"
        }
    }

    private func isModelRefusal(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.hasPrefix("i cannot") ||
               lower.hasPrefix("i can't") ||
               lower.hasPrefix("i'm unable") ||
               lower.hasPrefix("i am unable") ||
               lower.hasPrefix("i'm sorry") ||
               lower.hasPrefix("i apologize") ||
               lower.hasPrefix("sorry, i")
    }

    /// Strips common preamble patterns the model adds before the actual translation.
    private func stripPreamble(_ text: String) -> String {
        // "Sure, here is the text in English:\n\n..." → trim up to and including first blank line
        let preamblePatterns = [
            "sure, here",
            "here is the",
            "here's the",
            "of course,",
            "certainly,",
        ]
        let lower = text.lowercased()
        for pattern in preamblePatterns where lower.hasPrefix(pattern) {
            // The actual content starts after the first blank line (\n\n)
            if let range = text.range(of: "\n\n") {
                let content = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !content.isEmpty { return content }
            }
            // Or after the first colon
            if let range = text.range(of: ":") {
                let content = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !content.isEmpty { return content }
            }
        }
        return text
    }
}

private extension String {
    var words: [String] {
        components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    }
}
