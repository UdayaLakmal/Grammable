// Grammable — Copyright (C) 2026 Udaya Lakmal — GPL-3.0-or-later

import AppKit
import SwiftUI
import GrammableCore

/// Renders every pop-up state and Settings tab to PNG files, offscreen.
/// Used for visual checks, documentation screenshots and CI:  Grammable --render-ui <folder>
@MainActor
enum UISnapshot {

    static func renderAll(to directory: URL) -> Int32 {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let coordinator = PopupCoordinator.shared
        let sample = "i has went to the store yesterday and buyed three apple's for are lunch."
        let context = SelectionContext(text: sample, app: nil, anchor: .zero, isEditable: true, source: .mouse)
        let fix = BuiltInPresets.all.first { $0.id == "fix-grammar" }!
        let pro = BuiltInPresets.all.first { $0.id == "professional" }!
        let fixed = "I went to the store yesterday and bought three apples for our lunch."
        let fixResult = EngineResult(preset: fix, backend: .claude, original: sample, suggestion: fixed,
                                     diff: TextDiff(original: sample, revised: fixed), duration: 4.2)
        let casual = "hey can u send me that report asap, need it for the meeting thx"
        let polished = "Could you please send me the report as soon as possible? I need it for the meeting. Thank you."
        let proResult = EngineResult(preset: pro, backend: .ollama, original: casual, suggestion: polished,
                                     diff: TextDiff(original: casual, revised: polished), duration: 1.8)

        let states: [(String, PopupCoordinator.Phase, EngineResult?)] = [
            ("popup-1-trigger", .trigger, nil),
            ("popup-2-menu", .menu, nil),
            ("popup-3-working", .working(presetName: fix.name, backend: .claude), nil),
            ("popup-4-review-fix", .review, fixResult),
            ("popup-5-review-rewrite", .review, proResult),
            ("popup-6-error", .message(title: "Codex CLI couldn’t finish",
                                       detail: BackendError.notInstalled(.codex).localizedDescription, isError: true), nil),
        ]
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            for (name, phase, result) in states {
                coordinator.loadPreview(phase: phase, context: context, result: result)
                save(PopupRootView(coordinator: coordinator), size: nil, appearance: appearance,
                     to: directory.appendingPathComponent("\(name)-\(suffix).png"), background: true)
            }
        }

        let navigation = SettingsNavigation()
        for tab in [SettingsTab.general, .backends, .presets, .privacy, .about] {
            navigation.tab = tab
            save(SettingsView(navigation: navigation), size: NSSize(width: 620, height: 520), appearance: .aqua,
                 to: directory.appendingPathComponent("settings-\(tab.rawValue).png"), background: false, settle: 2.5)
        }
        coordinator.dismiss()
        print("Rendered UI to \(directory.path)")
        return 0
    }

    private static func save<V: View>(_ view: V, size: NSSize?, appearance: NSAppearance.Name, to url: URL,
                                      background: Bool, settle: TimeInterval = 0.4) {
        let root = view
            .padding(background ? 16 : 0)
            .background(background ? Color(nsColor: appearance == .aqua
                ? NSColor(white: 0.93, alpha: 1) : NSColor(white: 0.16, alpha: 1)) : Color.clear)
        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: appearance)
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 600, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        let fitting = size ?? host.fittingSize
        window.setContentSize(fitting)
        host.frame = NSRect(origin: .zero, size: fitting)
        RunLoop.main.run(until: Date().addingTimeInterval(settle))
        host.layoutSubtreeIfNeeded()
        host.display()

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.orderOut(nil)
    }
}
