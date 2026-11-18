// Grammable — Copyright (C) 2026 Udaya Lakmal — GPL-3.0-or-later

import AppKit
import SwiftUI
import GrammableCore

/// A borderless floating panel that never steals focus from the app you're writing in.
final class FloatingPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 40, height: 40),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered, defer: true
        )
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true } // lets the rewrite editor receive typing
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { PopupCoordinator.shared.dismiss() } // Esc
}

/// Lets the very first click on the floating panel press the button under the mouse
/// (macOS 12 otherwise spends that click making the panel key).
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Drives the popup: trigger button → action menu → working → review.
@MainActor
final class PopupCoordinator: ObservableObject {
    static let shared = PopupCoordinator()

    enum Phase: Equatable {
        case hidden
        case trigger
        case menu
        case working(presetName: String, backend: BackendID)
        case review
        case message(title: String, detail: String, isError: Bool)
    }

    @Published private(set) var phase: Phase = .hidden
    @Published private(set) var presets: [Preset] = []
    @Published private(set) var result: EngineResult?
    @Published var accepted: Set<Int> = []
    @Published var editedSuggestion = ""
    /// Set when the default AI can't be used, so the menu can say how to set one up.
    @Published private(set) var missingBackendDetail: String?
    @Published var isHoveringTrigger = false { didSet { if isHoveringTrigger { autoHide?.cancel() } else { scheduleAutoHide() } } }

    private(set) var context: SelectionContext?
    private var lastPreset: Preset?
    private var task: Task<Void, Never>?
    private var autoHide: DispatchWorkItem?
    private let panel = FloatingPanel()
    private let settings = AppSettings.shared
    private let store = PresetStore()
    private lazy var hostingView = FirstClickHostingView(rootView: PopupRootView(coordinator: self))

    private init() {
        panel.contentView = hostingView
    }

    var isVisible: Bool { phase != .hidden }
    var defaultBackend: BackendID { settings.defaultBackend }

    func backend(for preset: Preset) -> BackendID {
        GrammableEngine.resolveBackend(for: preset, default: settings.defaultBackend)
    }

    // MARK: Entry points

    /// Small round button next to a fresh selection.
    func showTrigger(for context: SelectionContext) {
        if case .working = phase { return }
        if phase == .review || phase == .menu { return }
        self.context = context
        phase = .trigger
        layout()
        scheduleAutoHide()
    }

    /// Opens the action menu directly (hotkey or menu bar).
    func showMenu(for context: SelectionContext) {
        cancelTask()
        self.context = context
        openMenu()
    }

    func showMessage(_ title: String, detail: String, isError: Bool, at anchor: NSRect? = nil) {
        if let anchor, context == nil {
            context = SelectionContext(text: "", app: nil, anchor: anchor, isEditable: false, source: .hotkey)
        }
        phase = .message(title: title, detail: detail, isError: isError)
        layout()
    }

    func openMenu() {
        autoHide?.cancel()
        if let context, context.needsCopy {
            // The app hid the selection from Accessibility: copy it now (clipboard is restored).
            Task {
                let text = await AccessibilityService.copySelectionUsingClipboard() ?? ""
                if text.trimmingCharacters(in: .whitespacesAndNewlines).count < settings.minSelectionLength {
                    DiagnosticLog.log("copy fallback found no text")
                    dismiss()
                    return
                }
                self.context = context.with(text: text)
                openMenu()
            }
            return
        }
        reloadPresets()
        phase = .menu
        layout()
        checkDefaultBackend()
    }

    private func checkDefaultBackend() {
        let id = settings.defaultBackend
        let configuration = settings.backendConfiguration
        Task { [weak self] in
            let status = await BackendFactory.make(id, configuration: configuration).checkAvailability()
            guard let self, self.phase == .menu else { return }
            let detail = status.isAvailable ? nil : status.detail
            if detail != self.missingBackendDetail {
                self.missingBackendDetail = detail
                if detail != nil { DiagnosticLog.log("default AI unavailable: \(id.rawValue)") }
                self.layout()
            }
        }
    }

    // MARK: Running

    func run(_ preset: Preset) {
        guard let context else { return }
        lastPreset = preset
        cancelTask()
        let backendID = backend(for: preset)
        phase = .working(presetName: preset.name, backend: backendID)
        layout()

        let configuration = settings.backendConfiguration
        let defaultBackend = settings.defaultBackend
        task = Task { [weak self] in
            do {
                let result = try await GrammableEngine.run(
                    preset: preset, text: context.text,
                    defaultBackend: defaultBackend, configuration: configuration
                )
                guard let self, !Task.isCancelled else { return }
                self.result = result
                self.accepted = Set(result.diff.changes.map(\.id))
                self.editedSuggestion = result.suggestion
                self.phase = .review
                self.layout()
            } catch {
                guard let self, !Task.isCancelled else { return }
                if let backendError = error as? BackendError, backendError == .cancelled { return }
                self.phase = .message(
                    title: "\(backendID.displayName) couldn’t finish",
                    detail: error.localizedDescription, isError: true
                )
                self.layout()
            }
        }
    }

    func retry() {
        if let lastPreset { run(lastPreset) }
    }

    // MARK: Results

    var finalText: String {
        guard let result else { return "" }
        return result.preset.mode == .fix ? result.diff.apply(accepted: accepted) : editedSuggestion
    }

    func toggle(_ change: TextChange) {
        if accepted.contains(change.id) { accepted.remove(change.id) } else { accepted.insert(change.id) }
    }

    func setAll(_ on: Bool) {
        accepted = on ? Set(result?.diff.changes.map(\.id) ?? []) : []
    }

    func replace() {
        let text = finalText
        let app = context?.app
        dismiss()
        Task { await AccessibilityService.paste(text, into: app) }
    }

    func copy() {
        AccessibilityService.copyToClipboard(finalText)
        dismiss()
    }

    // MARK: Dismissal

    /// Called for clicks, typing or scrolling in other apps.
    func userInteractedElsewhere() {
        // Any click, keystroke or scroll in another app means the user moved on.
        // Closing keeps "Replace" from ever pasting into the wrong place.
        if phase != .hidden { dismiss() }
    }

    func dismiss() {
        cancelTask()
        autoHide?.cancel()
        phase = .hidden
        result = nil
        panel.orderOut(nil)
    }

    private func cancelTask() {
        task?.cancel()
        task = nil
    }

    private func scheduleAutoHide() {
        autoHide?.cancel()
        guard phase == .trigger else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.phase == .trigger, !self.isHoveringTrigger else { return }
            self.dismiss()
        }
        autoHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    func reloadPresets() {
        let loaded = store.load()
        presets = loaded.presets
        if !loaded.errors.isEmpty {
            NSLog("Grammable preset errors: %@", loaded.errors.joined(separator: "; "))
        }
    }

    /// Puts the coordinator into a given state without showing the panel (used by `--render-ui`).
    func loadPreview(phase: Phase, context: SelectionContext, result: EngineResult? = nil) {
        self.context = context
        self.result = result
        if let result {
            accepted = Set(result.diff.changes.map(\.id))
            editedSuggestion = result.suggestion
        }
        reloadPresets()
        self.phase = phase
    }

    // MARK: Layout

    /// Sizes the panel to its SwiftUI content and places it next to the selection, on screen.
    private func layout() {
        // Let SwiftUI render the new phase first so the measured size is current.
        DispatchQueue.main.async { [weak self] in self?.performLayout() }
    }

    private func performLayout() {
        guard let context, phase != .hidden else { return }
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        let anchor = context.anchor
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor.insetBy(dx: -2, dy: -2)) })
            ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let gap: CGFloat = phase == .trigger ? 6 : 10

        var origin: NSPoint
        if phase == .trigger {
            origin = NSPoint(x: anchor.maxX + gap, y: anchor.minY - size.height - gap)
        } else {
            origin = NSPoint(x: anchor.minX - 12, y: anchor.minY - size.height - gap)
            if origin.y < visible.minY { origin.y = anchor.maxY + gap } // not enough room below → above
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)

        let wasVisible = panel.isVisible
        panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: wasVisible && phase != .trigger)
        if !wasVisible { panel.orderFrontRegardless() }
        // Take keyboard focus (Esc, 1-9, Return, editing) without activating the app,
        // so the text field you were writing in keeps its selection.
        if phase != .trigger { panel.makeKey() }
    }
}
