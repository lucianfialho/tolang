import AppKit
import SwiftUI

public class SubtitleState: ObservableObject {
    @Published public var originalText: String = ""
    @Published public var translatedText: String = ""
    @Published public var partialText: String = ""
    @Published public var isListening: Bool = false
    @Published public var contextLabel: String = ""
    @Published public var contextIcon: String = "mic.fill"
}

private let kFrameKey = "ToLang.SubtitleOverlay.frame"

public class SubtitleOverlay: NSPanel {
    public let state = SubtitleState()

    public init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 120),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless, .resizable],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .screenSaver
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = true
        minSize = NSSize(width: 300, height: 80)

        DispatchQueue.main.async {
            let hosting = NSHostingView(rootView: SubtitleView(state: self.state))
            hosting.layer?.backgroundColor = .clear
            self.contentView = hosting
        }
    }

    public func showOnScreen() {
        if let saved = UserDefaults.standard.string(forKey: kFrameKey),
           let f = NSRectFromString(saved) as NSRect?,
           f.width >= 300, isFullyOnScreen(f) {
            setFrame(f, display: true)
        } else {
            UserDefaults.standard.removeObject(forKey: kFrameKey)
            resetToDefaultPosition()
        }
        orderFrontRegardless()
    }

    public func hide() { saveFrame(); orderOut(nil) }
    public override var canBecomeKey: Bool { false }

    public override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        if isVisible { saveFrame() }
    }

    private func saveFrame() {
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: kFrameKey)
    }

    private func resetToDefaultPosition() {
        guard let screen = NSScreen.main else { return }
        let sf = screen.visibleFrame
        let w = min(720.0, sf.width - 80)
        setFrame(NSRect(x: sf.midX - w / 2, y: sf.minY + 40, width: w, height: 120), display: true)
    }

    private func isFullyOnScreen(_ f: NSRect) -> Bool {
        NSScreen.screens.contains { $0.visibleFrame.contains(f) }
    }
}

private struct SubtitleView: View {
    @ObservedObject var state: SubtitleState
    @State private var pulse = false

    private var showOverlay: Bool {
        state.isListening || !state.translatedText.isEmpty
    }

    var body: some View {
        ZStack {
            if showOverlay {
                VStack(alignment: .leading, spacing: 8) {
                    // Header row
                    HStack(spacing: 6) {
                        if !state.contextLabel.isEmpty {
                            Image(systemName: state.contextIcon)
                                .font(.system(size: 10, weight: .medium))
                            Text(state.contextLabel)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .lineLimit(1)
                        }
                        Spacer()
                        if state.isListening {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(.red.opacity(pulse ? 0.45 : 1))
                                    .frame(width: 6, height: 6)
                                    .animation(.easeInOut(duration: 0.8).repeatForever(), value: pulse)
                                Text("ao vivo")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .foregroundStyle(.secondary)

                    // Body
                    if !state.translatedText.isEmpty {
                        Text(state.translatedText)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            ))
                    } else if !state.partialText.isEmpty {
                        Text(state.partialText)
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if state.isListening {
                        HStack(spacing: 6) {
                            ForEach(0..<3, id: \.self) { i in
                                Circle()
                                    .fill(.secondary.opacity(0.5))
                                    .frame(width: 6, height: 6)
                                    .scaleEffect(pulse ? 1.4 : 0.8)
                                    .animation(
                                        .easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15),
                                        value: pulse
                                    )
                            }
                            Text("ouvindo…")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    // Original below translation
                    if !state.translatedText.isEmpty, !state.originalText.isEmpty {
                        Text(state.originalText)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(8)
                .animation(.spring(duration: 0.3), value: state.translatedText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { pulse = true }
    }
}
