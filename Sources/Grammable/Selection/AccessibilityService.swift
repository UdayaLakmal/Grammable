// Grammable — Copyright (C) 2026 Udaya Lakmal — GPL-3.0-or-later

import AppKit
import ApplicationServices

/// Reads the selection in other apps and puts edited text back, using the
/// macOS Accessibility API (with a clipboard fallback for apps that do not expose it).
enum AccessibilityService {

    // MARK: Permission

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to System Settings › Privacy & Security › Accessibility.
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Reading

    private static let systemWide: AXUIElement = {
        let element = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(element, 0.4) // never hang on an unresponsive app
        return element
    }()

    static func focusedElement() -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.4)
        return element
    }

    static func selectedText(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    static func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    /// Password fields must never be read or sent anywhere.
    static func isSecureField(_ element: AXUIElement) -> Bool {
        stringAttribute(element, kAXSubroleAttribute) == (kAXSecureTextFieldSubrole as String)
            || stringAttribute(element, kAXRoleAttribute) == "AXSecureTextField"
    }

    /// Whether text in the element can be replaced (text fields, text views, editable web content).
    static func isEditable(_ element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
           settable.boolValue { return true }
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success,
           settable.boolValue { return true }
        let role = stringAttribute(element, kAXRoleAttribute) ?? ""
        return role == kAXTextAreaRole as String || role == kAXTextFieldRole as String || role == "AXComboBox"
    }

    /// Screen rectangle of the selection in AppKit coordinates (bottom-left origin), if the app reports it.
    static func selectionBounds(of element: AXUIElement) -> NSRect? {
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue else { return nil }
        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
                element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &boundsValue) == .success,
              let boundsValue, CFGetTypeID(boundsValue) == AXValueGetTypeID()
        else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect), rect.width > 0 || rect.height > 0 else { return nil }
        // AX uses top-left origin relative to the primary screen.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    private static var preparedPIDs = Set<pid_t>()

    /// Chromium/Electron apps (Slack, Discord, VS Code, Notion…) only build their
    /// accessibility tree when asked. This flag asks politely and is harmless elsewhere.
    static func prepare(app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard !preparedPIDs.contains(pid) else { return }
        preparedPIDs.insert(pid)
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.3)
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    // MARK: Clipboard fallback

    /// Copies the current selection with ⌘C and restores the user's clipboard afterwards.
    static func copySelectionUsingClipboard() async -> String? {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        let before = pasteboard.changeCount
        postKey(KeyCode.c, flags: .maskCommand)

        var text: String?
        for _ in 0..<20 { // up to ~0.5s
            try? await Task.sleep(nanoseconds: 25_000_000)
            if pasteboard.changeCount != before {
                text = pasteboard.string(forType: .string)
                break
            }
        }
        if pasteboard.changeCount != before { snapshot.restore(to: pasteboard) }
        return text
    }

    /// Replaces the current selection in the frontmost app by pasting, then restores the clipboard.
    static func paste(_ text: String, into app: NSRunningApplication?) async {
        if let app, !app.isActive {
            app.activate(options: [])
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        // Ask clipboard-history apps to ignore this temporary entry.
        item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType"))
        pasteboard.writeObjects([item])
        let ours = pasteboard.changeCount

        postKey(KeyCode.v, flags: .maskCommand)
        try? await Task.sleep(nanoseconds: 450_000_000)
        if pasteboard.changeCount == ours { snapshot.restore(to: pasteboard) }
    }

    static func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    static let syntheticEventTag: Int64 = 0x4752_4D42 // "GRMB"

    enum KeyCode {
        static let c: CGKeyCode = 8
        static let v: CGKeyCode = 9
    }

    private static func postKey(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        // Tag our own synthetic keystrokes so SelectionMonitor can ignore them.
        down?.setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)
        up?.setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

/// A full copy of the clipboard (all items, all types) so it can be restored.
struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { dict[type] = data }
            }
            return dict
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restored: [NSPasteboardItem] = items.map { dict in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}
