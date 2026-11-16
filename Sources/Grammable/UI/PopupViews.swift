// Grammable — Copyright (C) 2026 Udaya Lakmal — GPL-3.0-or-later

import SwiftUI
import GrammableCore

struct PopupRootView: View {
    @ObservedObject var coordinator: PopupCoordinator

    var body: some View {
        Group {
            switch coordinator.phase {
            case .hidden:
                Color.clear.frame(width: 1, height: 1)
            case .trigger:
                TriggerButton(coordinator: coordinator)
            case .menu:
                ActionMenuView(coordinator: coordinator).card()
            case .working(let name, let backend):
                WorkingView(presetName: name, backend: backend, cancel: coordinator.dismiss).card()
            case .review:
                if let result = coordinator.result {
                    ReviewView(coordinator: coordinator, result: result).card()
                }
            case .message(let title, let detail, let isError):
                MessageView(title: title, detail: detail, isError: isError, coordinator: coordinator).card()
            }
        }
        .fixedSize()
    }
}

private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            )
            .padding(1)
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }
}

// MARK: - Trigger

struct TriggerButton: View {
    @ObservedObject var coordinator: PopupCoordinator

    var body: some View {
        Button(action: coordinator.openMenu) {
            ZStack {
                Circle().fill(Brand.gradient)
                Text("G")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Image(systemName: "sparkle")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: 7, y: -7)
            }
            .frame(width: 28, height: 28)
            .scaleEffect(coordinator.isHoveringTrigger ? 1.12 : 1)
            .shadow(color: Brand.violet.opacity(0.45), radius: 4, y: 1)
            .animation(.spring(response: 0.25), value: coordinator.isHoveringTrigger)
        }
        .buttonStyle(.plain)
        .padding(4)
        .onHover { coordinator.isHoveringTrigger = $0 }
        .help("Grammable — fix, rewrite or change the tone (\(HotKey.defaultDisplay))")
    }
}

// MARK: - Action menu

struct ActionMenuView: View {
    @ObservedObject var coordinator: PopupCoordinator
    @State private var hovered: String?

    private var wordCount: Int {
        coordinator.context?.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("Grammable").font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.gradient)
                Text("· \(wordCount) word\(wordCount == 1 ? "" : "s")")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                PrivacyBadge(backend: coordinator.defaultBackend)
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)

            Divider().padding(.horizontal, 8)

            VStack(spacing: 1) {
                ForEach(Array(coordinator.presets.enumerated()), id: \.element.id) { index, preset in
                    row(preset, index: index)
                }
            }
            .padding(6)

            Divider().padding(.horizontal, 8)

            HStack {
                Text("Using \(coordinator.defaultBackend.displayName)")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    coordinator.dismiss()
                    AppDelegate.shared?.openSettings(tab: .presets)
                } label: {
                    Image(systemName: "gearshape").font(.system(size: 11))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Presets & settings")
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
        }
        .frame(width: 270)
    }

    private func row(_ preset: Preset, index: Int) -> some View {
        let backend = coordinator.backend(for: preset)
        return Button { coordinator.run(preset) } label: {
            HStack(spacing: 9) {
                Image(systemName: preset.icon)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(hovered == preset.id ? AnyShapeStyle(.white) : AnyShapeStyle(Brand.gradient))
                Text(preset.name).font(.system(size: 13))
                Spacer(minLength: 8)
                if backend != coordinator.defaultBackend {
                    Text(backend.shortName)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                if index < 9 {
                    Text("\(index + 1)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .foregroundStyle(hovered == preset.id ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hovered == preset.id ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(index < 9 ? KeyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: []) : nil)
        .onHover { if $0 { hovered = preset.id } else if hovered == preset.id { hovered = nil } }
    }
}

// MARK: - Working

struct WorkingView: View {
    let presetName: String
    let backend: BackendID
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(presetName).font(.system(size: 12, weight: .semibold))
                HStack(spacing: 4) {
                    Text("Asking \(backend.displayName)…").font(.system(size: 11)).foregroundStyle(.secondary)
                    PrivacyBadge(backend: backend)
                }
            }
            Spacer(minLength: 12)
            Button("Cancel", action: cancel).controlSize(.small).keyboardShortcut(.cancelAction)
        }
        .padding(12)
        .frame(width: 320)
    }
}

// MARK: - Review

struct ReviewView: View {
    @ObservedObject var coordinator: PopupCoordinator
    let result: EngineResult
    @State private var showOriginal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if result.isUnchanged {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).font(.title2)
                    VStack(alignment: .leading) {
                        Text("Looks good!").font(.headline)
                        Text("No changes suggested.").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            } else if result.preset.mode == .fix {
                fixBody
            } else {
                rewriteBody
            }
            footer
        }
        .padding(14)
        .frame(width: 480)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: result.preset.icon).foregroundStyle(Brand.gradient)
            Text(result.preset.name).font(.system(size: 13, weight: .semibold))
            PrivacyBadge(backend: result.backend)
            Text(String(format: "%.1fs", result.duration)).font(.system(size: 10)).foregroundStyle(.tertiary)
            Spacer()
            Button(action: coordinator.dismiss) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain).help("Close (Esc)")
        }
    }

    // Grammar / spelling: highlighted preview + per-change checklist.
    private var fixBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                Text(highlighted)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxHeight: 170)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))

            HStack {
                Text("\(coordinator.accepted.count) of \(result.diff.changes.count) changes")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button("Accept all") { coordinator.setAll(true) }.buttonStyle(.link).font(.system(size: 11))
                Button("Reject all") { coordinator.setAll(false) }.buttonStyle(.link).font(.system(size: 11))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(result.diff.changes) { change in
                        ChangeRow(change: change, isOn: coordinator.accepted.contains(change.id)) {
                            coordinator.toggle(change)
                        }
                    }
                }
            }
            .frame(maxHeight: 150)
        }
    }

    private var highlighted: AttributedString {
        var out = AttributedString()
        for segment in result.diff.segments {
            switch segment {
            case .same(let s):
                out += AttributedString(s)
            case .change(let c):
                if coordinator.accepted.contains(c.id) {
                    if !c.original.isEmpty {
                        var removed = AttributedString(c.original)
                        removed.strikethroughStyle = .single
                        removed.foregroundColor = .red.opacity(0.7)
                        out += removed
                    }
                    if !c.replacement.isEmpty {
                        var added = AttributedString(c.replacement)
                        added.foregroundColor = .green
                        added.backgroundColor = .green.opacity(0.15)
                        out += added
                    }
                } else {
                    var kept = AttributedString(c.original)
                    kept.underlineStyle = .single
                    out += kept
                }
            }
        }
        return out
    }

    // Tone / rewrite / format: editable result, optional original.
    private var rewriteBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $coordinator.editedSuggestion)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: editorHeight)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))

            DisclosureGroup(isExpanded: $showOriginal) {
                ScrollView {
                    Text(result.original)
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
            } label: {
                Text("Original").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
    }

    /// Rough height for the editor so the card fits its content (90–260 pt).
    private var editorHeight: CGFloat {
        let text = result.suggestion
        let wrapped = text.split(separator: "\n", omittingEmptySubsequences: false)
            .reduce(0) { $0 + max(1, Int(ceil(Double($1.count) / 62.0))) }
        return min(260, max(90, CGFloat(wrapped) * 17 + 18))
    }

    private var footer: some View {
        HStack {
            Button {
                coordinator.retry()
            } label: { Label("Retry", systemImage: "arrow.clockwise") }
            .help("Ask again for a different suggestion")

            Spacer()

            Button("Copy") { coordinator.copy() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            if result.isUnchanged {
                Button("Done") { coordinator.dismiss() }.keyboardShortcut(.defaultAction)
            } else {
                Button(coordinator.context?.isEditable == false ? "Paste over selection" : "Replace") {
                    coordinator.replace()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(result.preset.mode == .fix && coordinator.accepted.isEmpty)
            }
        }
        .controlSize(.regular)
    }
}

struct ChangeRow: View {
    let change: TextChange
    let isOn: Bool
    let toggle: () -> Void

    private func visible(_ s: String) -> String {
        if s.isEmpty { return "∅" }
        if s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return s.contains("\n") ? "↵ line break" : "␣ space"
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.secondary))
                if !change.isInsertion {
                    Text(visible(change.original)).strikethrough().foregroundStyle(.red.opacity(0.8))
                }
                if !change.isInsertion && !change.isDeletion {
                    Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                if !change.isDeletion {
                    Text(visible(change.replacement)).foregroundStyle(.green)
                }
                Spacer()
                Text(change.isInsertion ? "add" : change.isDeletion ? "remove" : "replace")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            .font(.system(size: 12))
            .lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Message

struct MessageView: View {
    let title: String
    let detail: String
    let isError: Bool
    @ObservedObject var coordinator: PopupCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .foregroundStyle(isError ? Color.orange : Color.blue)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                if isError {
                    Button("AI Settings…") {
                        coordinator.dismiss()
                        AppDelegate.shared?.openSettings(tab: .backends)
                    }
                    Button("Retry") { coordinator.retry() }
                }
                Spacer()
                Button("Close") { coordinator.dismiss() }.keyboardShortcut(.defaultAction)
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 360)
    }
}
