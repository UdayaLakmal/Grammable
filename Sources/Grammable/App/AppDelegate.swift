// Grammable — Copyright (C) 2026 Udaya Lakmal — GPL-3.0-or-later

import AppKit
import Combine
import SwiftUI
import GrammableCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static private(set) weak var shared: AppDelegate?

    private let settings = AppSettings.shared
    private let monitor = SelectionMonitor()
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var settingsWindow: NSWindow?
    private let navigation = SettingsNavigation()
    private var trustTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        setUpStatusItem()
        NSLog("Grammable %@ started. Accessibility trusted: %@", Brand.version,
              AccessibilityService.isTrusted ? "yes" : "no")

        let popup = PopupCoordinator.shared
        monitor.onSelection = { context in
            Task { @MainActor in popup.showTrigger(for: context) }
        }
        monitor.onInteraction = {
            Task { @MainActor in popup.userInteractedElsewhere() }
        }
        monitor.start()

        hotKey = HotKey(keyCode: HotKey.defaultKeyCode, modifiers: HotKey.defaultModifiers) { [weak self] in
            Task { @MainActor in await self?.invokeOnSelection() }
        }

        settings.$isEnabled
            .sink { [weak self] enabled in self?.statusItem.button?.image = Brand.menuBarImage(enabled: enabled) }
            .store(in: &cancellables)

        if !AccessibilityService.isTrusted {
            watchForTrust()
        }
        if !settings.hasCompletedOnboarding || !AccessibilityService.isTrusted {
            openSettings(tab: .general)
            if !AccessibilityService.isTrusted { AccessibilityService.requestTrust() }
        }

        // Pick a sensible default backend on first launch: the first one that is installed.
        if !settings.hasChosenBackend {
            let config = settings.backendConfiguration
            Task { [settings] in
                for id in [BackendID.claude, .codex, .gemini, .apple, .ollama, .openAICompatible] {
                    if await BackendFactory.make(id, configuration: config).checkAvailability().isAvailable {
                        settings.defaultBackend = id
                        return
                    }
                }
            }
        }
    }

    /// Opening Grammable again (Finder, Spotlight, Launchpad) shows Settings. This matters because
    /// macOS hides menu bar icons behind the notch when the menu bar is full.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings(tab: .general)
        return true
    }

    /// Global monitors need Accessibility; restart them once the user grants it.
    private func watchForTrust() {
        trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard AccessibilityService.isTrusted else { return }
                timer.invalidate()
                NSLog("Grammable: Accessibility granted, starting selection monitor")
                self?.monitor.start()
                self?.statusItem.menu = self?.buildMenu()
            }
        }
    }

    // MARK: Hotkey / menu action

    /// ⌃⌥G or "Improve Selected Text": read the selection (Accessibility, then ⌘C fallback) and open the menu.
    func invokeOnSelection() async {
        guard settings.isEnabled else { return }
        let popup = PopupCoordinator.shared
        let mouse = NSEvent.mouseLocation
        let mouseAnchor = NSRect(x: mouse.x, y: mouse.y, width: 1, height: 1)

        guard AccessibilityService.isTrusted else {
            AccessibilityService.requestTrust()
            popup.showMessage("Accessibility access needed",
                              detail: "Allow Grammable in System Settings › Privacy & Security › Accessibility, then try again.",
                              isError: true, at: mouseAnchor)
            return
        }

        if let context = SelectionMonitor.currentSelection(source: .hotkey, mouse: mouse, settings: settings) {
            popup.showMenu(for: context)
            return
        }

        // Fallback for apps without Accessibility text support: copy the selection.
        let app = NSWorkspace.shared.frontmostApplication
        if let bundleID = app?.bundleIdentifier, settings.excludedBundleIDs.contains(bundleID) { return }
        if let text = await AccessibilityService.copySelectionUsingClipboard(),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            popup.showMenu(for: SelectionContext(text: text, app: app, anchor: mouseAnchor, isEditable: true, source: .hotkey))
        } else {
            popup.showMessage("Select some text first",
                              detail: "Highlight text in any app, then press \(HotKey.defaultDisplay) or click the G button.",
                              isError: false, at: mouseAnchor)
        }
    }

    // MARK: Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Brand.menuBarImage(enabled: settings.isEnabled)
        statusItem.button?.toolTip = "Grammable"
        statusItem.autosaveName = "GrammableStatusItem"
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        return menu
    }

    /// Rebuilt every time it opens so it always reflects current state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let title = NSMenuItem(title: "Grammable", action: nil, keyEquivalent: "")
        title.attributedTitle = NSAttributedString(string: "Grammable", attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
        menu.addItem(title)

        if !AccessibilityService.isTrusted {
            menu.addItem(item("⚠︎ Grant Accessibility Access…", #selector(grantAccess)))
        }

        menu.addItem(.separator())
        let enabled = item("Enabled", #selector(toggleEnabled), key: "e")
        enabled.state = settings.isEnabled ? .on : .off
        menu.addItem(enabled)

        let popup = item("Show Button on Text Selection", #selector(togglePopup))
        popup.state = settings.popupOnSelection ? .on : .off
        popup.isEnabled = settings.isEnabled
        menu.addItem(popup)

        let improve = item("Improve Selected Text  (\(HotKey.defaultDisplay))", #selector(improveSelection))
        improve.isEnabled = settings.isEnabled
        menu.addItem(improve)

        menu.addItem(.separator())
        let backendItem = NSMenuItem(title: "Default AI: \(settings.defaultBackend.displayName)", action: nil, keyEquivalent: "")
        let backendMenu = NSMenu()
        for id in BackendID.allCases {
            let b = item("\(id.displayName)\(id.isOnDevice ? "  🔒" : "  ☁︎")", #selector(chooseBackend(_:)))
            b.representedObject = id.rawValue
            b.state = id == settings.defaultBackend ? .on : .off
            backendMenu.addItem(b)
        }
        backendMenu.addItem(.separator())
        backendMenu.addItem(item("AI Backend Settings…", #selector(openBackendSettings)))
        backendItem.submenu = backendMenu
        menu.addItem(backendItem)

        menu.addItem(item("Edit Presets…", #selector(openPresetSettings)))
        menu.addItem(item("Open Presets Folder", #selector(openPresetsFolder)))

        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openGeneralSettings), key: ","))
        menu.addItem(item("Check for Updates…", #selector(openReleases)))
        menu.addItem(item("☕ Support Grammable on Ko-fi", #selector(openSponsor)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Grammable", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func toggleEnabled() {
        settings.isEnabled.toggle()
        if !settings.isEnabled { PopupCoordinator.shared.dismiss() }
    }
    @objc private func togglePopup() { settings.popupOnSelection.toggle() }
    @objc private func improveSelection() {
        // Give the menu time to close so the previous app is frontmost again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            Task { @MainActor in await self?.invokeOnSelection() }
        }
    }
    @objc private func chooseBackend(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let id = BackendID(rawValue: raw) {
            settings.defaultBackend = id
        }
    }
    @objc private func grantAccess() {
        AccessibilityService.requestTrust()
        AccessibilityService.openAccessibilitySettings()
    }
    @objc private func openGeneralSettings() { openSettings(tab: .general) }
    @objc private func openBackendSettings() { openSettings(tab: .backends) }
    @objc private func openPresetSettings() { openSettings(tab: .presets) }
    @objc private func openPresetsFolder() {
        if let dir = try? PresetStore().ensureDirectory() { NSWorkspace.shared.open(dir) }
    }
    @objc private func openReleases() { NSWorkspace.shared.open(Brand.releasesURL) }
    @objc private func openSponsor() { NSWorkspace.shared.open(Brand.sponsorURL) }

    // MARK: Settings window

    func openSettings(tab: SettingsTab) {
        navigation.tab = tab
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView(navigation: navigation))
            let window = NSWindow(contentViewController: controller)
            window.title = "Grammable Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
