// Grammable — Copyright (C) 2026 Udaya Lakmal — GPL-3.0-or-later

import Carbon.HIToolbox

/// A system-wide keyboard shortcut using the Carbon hot-key API
/// (works everywhere and needs no extra permission).
final class HotKey {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var eventHandlerInstalled = false
    private static var nextID: UInt32 = 1

    private var ref: EventHotKeyRef?
    private let id: UInt32

    /// Default shortcut: ⌃⌥G
    static let defaultKeyCode = UInt32(kVK_ANSI_G)
    static let defaultModifiers = UInt32(controlKey | optionKey)
    static let defaultDisplay = "⌃⌥G"

    init?(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        Self.installEventHandlerIfNeeded()
        id = Self.nextID
        Self.nextID += 1

        let hotKeyID = EventHotKeyID(signature: OSType(0x47524D42) /* 'GRMB' */, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { return nil }
        Self.handlers[id] = handler
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        Self.handlers[id] = nil
    }

    private static func installEventHandlerIfNeeded() {
        guard !eventHandlerInstalled else { return }
        eventHandlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            if let handler = HotKey.handlers[hotKeyID.id] {
                DispatchQueue.main.async(execute: handler)
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
