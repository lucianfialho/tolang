import SwiftUI
import ScreenCaptureKit

public struct ToLangSettingsView: View {
    @AppStorage("captureAppBundleID") private var captureAppBundleID: String = "com.hnc.Discord"
    @AppStorage("captureEnabled") private var captureEnabled: Bool = true

    @State private var availableApps: [SCRunningApplication] = []
    @State private var isLoadingApps = true

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("ToLang Settings")
                .font(.title2.bold())

            Divider()

            // App capture section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Capturar áudio do app", systemImage: "headphones")
                        .font(.headline)
                    Spacer()
                    Toggle("", isOn: $captureEnabled)
                        .labelsHidden()
                }

                Text("Selecione o app cujo áudio será capturado e traduzido (Discord, Zoom, etc).")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if captureEnabled {
                    HStack(spacing: 8) {
                        Picker("App", selection: $captureAppBundleID) {
                            if isLoadingApps {
                                // Keep the current selection valid while loading
                                Text(captureAppBundleID.isEmpty ? "Carregando…" : "\(appIcon(for: captureAppBundleID)) \(captureAppBundleID)")
                                    .tag(captureAppBundleID)
                            } else if availableApps.isEmpty {
                                Text("Nenhum app detectado").tag("")
                            }
                            ForEach(availableApps, id: \.bundleIdentifier) { app in
                                Text("\(appIcon(for: app.bundleIdentifier)) \(app.applicationName)")
                                    .tag(app.bundleIdentifier)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        if isLoadingApps {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Button {
                                Task { await loadApps() }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .help("Atualizar lista")
                        }
                    }

                    if !captureAppBundleID.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                            Text("Capturando: \(selectedAppName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding()
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

            // Hotkey info
            VStack(alignment: .leading, spacing: 8) {
                Label("Atalho de teclado", systemImage: "keyboard")
                    .font(.headline)
                HStack(spacing: 6) {
                    KeyBadge("⌘")
                    KeyBadge("⇧")
                    KeyBadge("L")
                    Text("Liga/desliga escuta")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

            Spacer()

            HStack {
                Spacer()
                Button("Fechar") { NSApp.keyWindow?.close() }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 440, height: 360)
        .task { await loadApps() }
    }

    private var selectedAppName: String {
        availableApps.first { $0.bundleIdentifier == captureAppBundleID }?.applicationName
            ?? captureAppBundleID
    }

    private func loadApps() async {
        isLoadingApps = true
        defer { isLoadingApps = false }

        guard let content = try? await SCShareableContent.current else { return }

        var seen = Set<String>()
        let all = content.applications
            .filter {
                !$0.bundleIdentifier.isEmpty &&
                $0.processID != ProcessInfo.processInfo.processIdentifier &&
                seen.insert($0.bundleIdentifier).inserted      // deduplicate by bundle ID
            }
            .sorted {
                let aVoice = AppAudioCapture.voiceAppBundleIDs.contains($0.bundleIdentifier)
                let bVoice = AppAudioCapture.voiceAppBundleIDs.contains($1.bundleIdentifier)
                if aVoice != bVoice { return aVoice }
                return $0.applicationName < $1.applicationName
            }

        availableApps = all

        // Auto-select first known voice app if saved choice isn't running
        if !all.contains(where: { $0.bundleIdentifier == captureAppBundleID }),
           let first = all.first(where: { AppAudioCapture.voiceAppBundleIDs.contains($0.bundleIdentifier) }) {
            captureAppBundleID = first.bundleIdentifier
        }
    }

    private func appIcon(for bundleID: String) -> String {
        switch bundleID {
        case "com.hnc.Discord":                        return "🎮"
        case "us.zoom.xos":                            return "📹"
        case "com.microsoft.teams2":                   return "💼"
        case "com.tinyspeck.slackmacgap":              return "#️⃣"
        case "com.apple.FaceTime":                     return "📱"
        case "com.google.Chrome", "com.apple.Safari":  return "🌐"
        default:                                       return "🔊"
        }
    }
}

private struct KeyBadge: View {
    let label: String
    init(_ label: String) { self.label = label }
    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
    }
}
