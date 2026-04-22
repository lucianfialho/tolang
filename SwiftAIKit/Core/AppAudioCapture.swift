import Foundation
import ScreenCaptureKit
import AVFoundation
import Speech
import OSLog

/// Captures audio output from a specific app (e.g. Discord) via ScreenCaptureKit.
/// Feed the output to a SFSpeechAudioBufferRecognitionRequest.
@MainActor
public class AppAudioCapture: NSObject, ObservableObject {
    @Published public var isCapturing = false

    private var stream: SCStream?
    private var request: SFSpeechAudioBufferRecognitionRequest?

    public var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    // MARK: - Public API

    /// Returns running apps that can be captured (filters to known voice apps by default).
    public static func availableApps() async -> [SCRunningApplication] {
        guard let content = try? await SCShareableContent.current else { return [] }
        return content.applications
            .filter { !$0.bundleIdentifier.isEmpty }
            .sorted { $0.applicationName < $1.applicationName }
    }

    public func start(app: SCRunningApplication) async throws {
        stop()

        let content = try await SCShareableContent.current
        guard let target = content.applications.first(where: { $0.processID == app.processID }) else {
            throw AppAudioError.appNotFound
        }

        let appFilter = SCContentFilter(display: content.displays[0], including: [target], exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 16000
        config.channelCount = 1
        // Minimize video overhead — we only need audio
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1) // 1 fps max

        ToLangLogger.capture.info("Starting capture for \(app.applicationName) (\(app.bundleIdentifier))")
        let s = SCStream(filter: appFilter, configuration: config, delegate: nil)
        try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global(qos: .userInteractive))
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .background))
        try await s.startCapture()
        stream = s
        isCapturing = true
        ToLangLogger.capture.info("✅ Capture started — audio: \(config.sampleRate)Hz")
    }

    public func stop() {
        if let s = stream {
            Task { try? await s.stopCapture() }
            stream = nil
        }
        isCapturing = false
    }

    // MARK: - Static helpers

    /// Known voice/video call app bundle IDs.
    public static let voiceAppBundleIDs: Set<String> = [
        "com.hnc.Discord",
        "us.zoom.xos",
        "com.microsoft.teams2",
        "com.google.Chrome",        // Meet runs in Chrome
        "com.apple.FaceTime",
        "com.tinyspeck.slackmacgap",
    ]

    public static func knownVoiceApps(from apps: [SCRunningApplication]) -> [SCRunningApplication] {
        apps.filter { voiceAppBundleIDs.contains($0.bundleIdentifier) }
    }
}

// MARK: - SCStreamOutput

extension AppAudioCapture: SCStreamOutput {
    nonisolated public func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return } // silently discard video frames
        guard let pcm = buffer.toPCMBuffer() else { return }
        Task { @MainActor in self.onBuffer?(pcm) }
    }
}

// MARK: - Error

public enum AppAudioError: Error, LocalizedError {
    case appNotFound
    case noDisplayAvailable
    public var errorDescription: String? {
        switch self {
        case .appNotFound:       return "App not found or not running."
        case .noDisplayAvailable: return "No display available for capture."
        }
    }
}

// MARK: - CMSampleBuffer → AVAudioPCMBuffer

private extension CMSampleBuffer {
    func toPCMBuffer() -> AVAudioPCMBuffer? {
        guard let desc = CMSampleBufferGetFormatDescription(self),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)
        else { return nil }

        let format = AVAudioFormat(streamDescription: asbd)!
        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(self))
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        pcm.frameLength = frameCount

        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
            self, at: 0, frameCount: Int32(frameCount),
            into: pcm.mutableAudioBufferList
        ) == noErr else { return nil }

        return pcm
    }
}
