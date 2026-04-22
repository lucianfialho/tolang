import AppKit
import SwiftUI

public class MenuBarManager: NSObject {
    private var statusItem: NSStatusItem?
    private var appName: String = ""
    private var iconSymbol: String = "translate"

    public var onToggleListening: (() -> Void)?
    public var onPairSelected: ((LanguagePair) -> Void)?
    public var onSettingsRequested: (() -> Void)?

    // Kept for template compatibility
    public override init() { super.init() }

    public func setup(appName: String, iconSymbol: String = "translate") {
        self.appName = appName
        self.iconSymbol = iconSymbol
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setIdle()
        rebuildMenu(activePair: nil, isListening: false)
    }

    public func rebuildMenu(activePair: LanguagePair?, isListening: Bool) {
        let menu = NSMenu()

        // Toggle listening
        let toggleTitle = isListening ? "Stop (⌘⇧L)" : "Start (⌘⇧L)"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggle), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        // Language pair presets
        let pairsHeader = NSMenuItem(title: "Translation", action: nil, keyEquivalent: "")
        pairsHeader.isEnabled = false
        menu.addItem(pairsHeader)

        for pair in LanguagePair.presets {
            let item = PairMenuItem(pair: pair, manager: self)
            item.state = (pair == activePair) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem?.menu = menu
    }

    public func setLoading(message: String = "Loading…") {
        guard let button = statusItem?.button else { return }
        button.title = "⏳"; button.image = nil; button.toolTip = message
    }

    public func setIdle() {
        guard let button = statusItem?.button else { return }
        button.title = ""
        button.image = NSImage(systemSymbolName: iconSymbol, accessibilityDescription: appName)
        button.toolTip = appName
    }

    public func setListening(pair: LanguagePair) {
        guard let button = statusItem?.button else { return }
        button.image = nil
        button.title = "🔴 \(pair.label)"
        button.toolTip = "Listening… ⌘⇧L to stop"
    }

    public func setError(message: String) {
        guard let button = statusItem?.button else { return }
        button.title = "⚠️"; button.image = nil; button.toolTip = message
    }

    @objc private func toggle() { onToggleListening?() }

    @objc func selectPair(_ sender: PairMenuItem) { onPairSelected?(sender.pair) }

    @objc private func openSettings() { onSettingsRequested?() }
}

final class PairMenuItem: NSMenuItem {
    let pair: LanguagePair
    init(pair: LanguagePair, manager: MenuBarManager) {
        self.pair = pair
        let title = "\(pair.source.flag) \(pair.source.name)  →  \(pair.target.flag) \(pair.target.name)"
        super.init(title: title, action: #selector(MenuBarManager.selectPair(_:)), keyEquivalent: "")
        self.target = manager
    }
    required init(coder: NSCoder) { fatalError() }
}
