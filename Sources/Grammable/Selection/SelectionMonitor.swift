// Grammable — Copyright (C) 2026 Udaya Lakmal — GPL-3.0-or-later

import AppKit
import ApplicationServices

/// Everything Grammable knows about a piece of selected text.
struct SelectionContext {
    enum Source { case mouse, keyboard, hotkey }

    let text: String
    let app: NSRunningApplication?
    /// Where to show the popup, in screen coordinates (bottom-left origin).
    let anchor: NSRect
    let isEditable: Bool
    let source: Source
}

/// Watches for text being selected in other apps (mouse drag, double/triple click,
/// Shift+arrow keys, ⌘A) and reports it, so the Grammable button can appear.
final class SelectionMonitor {
    var onSelection: ((SelectionContext) -> Void)?
    /// The user clicked, typed or scrolled somewhere else.
    var onInteraction: (() -> Void)?

    private var monitors: [Any] = []
    private var mouseDownLocation: NSPoint = .zero
    private var pending: DispatchWorkItem?
    private let settings = AppSettings.shared

    private static let selectionKeys: Set<UInt16> = [123, 124, 125, 126, 115, 119, 116, 121] // arrows, home, end, page up/down
    private static let keyA: UInt16 = 0

    func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp, .keyDown, .keyUp, .scrollWheel]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handle(event)
        }) {
            monitors.append(monitor)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        pending?.cancel()
    }

    private func handle(_ event: NSEvent) {
        if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == AccessibilityService.syntheticEventTag { return }
        switch event.type {
        case .leftMouseDown:
            mouseDownLocation = NSEvent.mouseLocation
            pending?.cancel()
            onInteraction?()

        case .leftMouseUp:
            let up = NSEvent.mouseLocation
            let distance = hypot(up.x - mouseDownLocation.x, up.y - mouseDownLocation.y)
            if distance >= 5 || event.clickCount >= 2 {
                schedule(source: .mouse, mouse: up)
            }

        case .keyDown:
            pending?.cancel()
            onInteraction?()

        case .keyUp:
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isShiftSelection = flags.contains(.shift) && Self.selectionKeys.contains(event.keyCode)
            let isSelectAll = flags.contains(.command) && event.keyCode == Self.keyA
            if isShiftSelection || isSelectAll {
                schedule(source: .keyboard, mouse: NSEvent.mouseLocation)
            }

        case .scrollWheel:
            onInteraction?()

        default:
            break
        }
    }

    private func schedule(source: SelectionContext.Source, mouse: NSPoint) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.inspect(source: source, mouse: mouse) }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    private func inspect(source: SelectionContext.Source, mouse: NSPoint) {
        guard settings.isEnabled, settings.popupOnSelection else {
            DiagnosticLog.log("skip: disabled (enabled=\(settings.isEnabled), popup=\(settings.popupOnSelection))"); return
        }
        guard AccessibilityService.isTrusted else {
            DiagnosticLog.log("skip: Accessibility permission not granted"); return
        }
        guard let context = Self.currentSelection(source: source, mouse: mouse, settings: settings) else { return }
        onSelection?(context)
    }

    /// Reads the current selection through Accessibility. Returns nil for excluded apps,
    /// password fields, or selections that are too short.
    static func currentSelection(source: SelectionContext.Source, mouse: NSPoint, settings: AppSettings) -> SelectionContext? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            DiagnosticLog.log("skip: no frontmost app"); return nil
        }
        let bundleID = app.bundleIdentifier ?? "?"
        guard bundleID != Bundle.main.bundleIdentifier else { return nil }
        guard !settings.excludedBundleIDs.contains(bundleID) else {
            DiagnosticLog.log("skip: \(bundleID) is excluded"); return nil
        }

        AccessibilityService.prepare(app: app)
        guard let element = AccessibilityService.focusedElement() else {
            DiagnosticLog.log("skip: \(bundleID) exposes no focused element"); return nil
        }
        guard !AccessibilityService.isSecureField(element) else {
            DiagnosticLog.log("skip: \(bundleID) password field"); return nil
        }
        let role = AccessibilityService.stringAttribute(element, kAXRoleAttribute) ?? "?"
        guard let text = AccessibilityService.selectedText(of: element) else {
            DiagnosticLog.log("skip: \(bundleID) \(role) has no selected-text attribute"); return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= settings.minSelectionLength, text.count <= 30_000 else {
            DiagnosticLog.log("skip: \(bundleID) \(role) selection length \(trimmed.count)"); return nil
        }
        DiagnosticLog.log("show: \(bundleID) \(role) selection length \(trimmed.count) via \(source)")

        let anchor: NSRect
        if source == .mouse {
            anchor = NSRect(x: mouse.x, y: mouse.y, width: 1, height: 1)
        } else {
            anchor = AccessibilityService.selectionBounds(of: element) ?? NSRect(x: mouse.x, y: mouse.y, width: 1, height: 1)
        }
        return SelectionContext(
            text: text, app: app, anchor: anchor,
            isEditable: AccessibilityService.isEditable(element), source: source
        )
    }
}
