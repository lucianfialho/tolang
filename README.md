# ToLang

> Real-time bilingual translation overlay for macOS — speak, and your words appear translated on screen.

ToLang sits in your menu bar and listens. When you speak Portuguese, it shows English on a floating overlay. When someone speaks English in Discord or Zoom, it shows Portuguese. All on-device, no API keys, no cloud.

![ToLang overlay with Liquid Glass UI on macOS 26](.github/preview.png)

---

## What it does

- **Mic → translation**: speak in your language, see the translation instantly on screen
- **App audio → translation**: captures Discord, Zoom, Teams audio and translates what others say back to you
- **Bidirectional**: auto-detects which language is being spoken and translates to the other
- **Any language pair**: Portuguese ↔ English, Spanish ↔ English, Japanese ↔ English, and more
- **Floating overlay**: stays on top of everything, movable, resizable, remembers position
- **Liquid Glass UI**: native macOS 26 glass effect that adapts to any background

## Requirements

- **macOS 26** (Tahoe) or later
- **Apple Silicon** with Apple Intelligence enabled in System Settings
- Xcode 26+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Getting started

```bash
git clone https://github.com/lucianfialho/tolang
cd tolang
xcodegen generate
open ToLang.xcodeproj
```

1. Set your **Team** in Xcode → Signing & Capabilities
2. `Cmd+R` to run
3. Click the menu bar icon → select your language pair → press `Cmd+Shift+L` to start listening

## Hotkey

`Cmd+Shift+L` — toggle listening on/off

## Language pairs

Open the menu bar icon to switch pairs:

| Pair | Direction |
|---|---|
| 🇧🇷 ↔ 🇺🇸 | Português ↔ English |
| 🇺🇸 ↔ 🇧🇷 | English ↔ Português |
| 🇪🇸 ↔ 🇺🇸 | Español ↔ English |
| 🇫🇷 ↔ 🇺🇸 | Français ↔ English |
| 🇩🇪 ↔ 🇺🇸 | Deutsch ↔ English |
| 🇯🇵 ↔ 🇺🇸 | 日本語 ↔ English |
| 🇨🇳 ↔ 🇺🇸 | 中文 ↔ English |

All pairs are bidirectional — ToLang detects which language is being spoken.

## Settings

Open **Settings** from the menu bar to choose which app's audio to capture (Discord, Zoom, Slack, Teams, etc.).

## How it works

```
Microphone ──► SFSpeechRecognizer (pt-BR) ──► silence detected ──► Apple Intelligence ──► overlay
Discord    ──► ScreenCaptureKit audio     ──► silence detected ──► Apple Intelligence ──► overlay
```

- Speech recognition runs on-device via `SFSpeechRecognizer`
- Translation runs on-device via `FoundationModels` (Apple Intelligence)
- App audio captured via `ScreenCaptureKit` — no virtual audio drivers needed
- Auto-recovery: watchdog restarts the recognizer if it goes silent

## Project structure

```
MyApp/
  MyAppApp.swift          app delegate, audio pipeline, translation logic
  AppConfig.swift         app name
SwiftAIKit/
  Core/
    LLMEngine.swift       Apple Intelligence session
    SpeechEngine.swift    microphone capture + SFSpeechRecognizer
    AppAudioCapture.swift ScreenCaptureKit app audio
    ContextDetector.swift detects frontmost app via Accessibility API
    MenuBarManager.swift  menu bar icon and language pair selector
    LanguagePair.swift    language model + presets
    ToLangLogger.swift    os.Logger categories
  UI/
    SubtitleOverlay.swift floating NSPanel + Liquid Glass SwiftUI view
    SettingsView.swift    app audio picker
```

## Privacy

Everything runs on your Mac. No audio, text, or translations are sent to any server. Apple Intelligence processes everything locally via the Apple Neural Engine.

## License

MIT
