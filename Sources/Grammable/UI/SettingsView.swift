// Grammable — Copyright (C) 2026 Udaya Lakmal — GPL-3.0-or-later

import AppKit
import SwiftUI
import GrammableCore

enum SettingsTab: String, Hashable {
    case general, backends, presets, privacy, about
}

final class SettingsNavigation: ObservableObject {
    @Published var tab: SettingsTab = .general
}

/// Live status of every backend, refreshed on demand.
@MainActor
final class BackendStatusModel: ObservableObject {
    @Published var statuses: [BackendID: BackendStatus] = [:]
    @Published var isRefreshing = false
    @Published var testResult: [BackendID: String] = [:]
    @Published var testing: Set<BackendID> = []

    /// Sample statuses for screenshots (`--render-ui`), so they never show this Mac's paths.
    static var demoStatuses: [BackendID: BackendStatus]?

    func refresh() {
        if let demo = Self.demoStatuses { statuses = demo; return }
        isRefreshing = true
        ShellEnvironment.shared.reset()
        let config = AppSettings.shared.backendConfiguration
        Task {
            await withTaskGroup(of: (BackendID, BackendStatus).self) { group in
                for id in BackendID.allCases {
                    group.addTask { (id, await BackendFactory.make(id, configuration: config).checkAvailability()) }
                }
                for await (id, status) in group { statuses[id] = status }
            }
            isRefreshing = false
        }
    }

    func test(_ id: BackendID) {
        testing.insert(id)
        testResult[id] = nil
        let config = AppSettings.shared.backendConfiguration
        let preset = Preset(id: "test", name: "Test", mode: .fix,
                            instructions: "Correct the spelling and grammar.")
        Task {
            do {
                let result = try await GrammableEngine.run(
                    preset: preset, text: "this sentense have two mistake.",
                    defaultBackend: id, configuration: config)
                testResult[id] = "✓ \(String(format: "%.1fs", result.duration)): “\(result.suggestion)”"
            } catch {
                testResult[id] = "✗ \(error.localizedDescription)"
            }
            testing.remove(id)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var navigation: SettingsNavigation

    var body: some View {
        TabView(selection: $navigation.tab) {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsTab.general)
            BackendSettings().tabItem { Label("AI Backends", systemImage: "cpu") }.tag(SettingsTab.backends)
            PresetSettings().tabItem { Label("Presets", systemImage: "list.star") }.tag(SettingsTab.presets)
            PrivacySettings().tabItem { Label("Privacy", systemImage: "hand.raised") }.tag(SettingsTab.privacy)
            AboutView().tabItem { Label("About", systemImage: "info.circle") }.tag(SettingsTab.about)
        }
        .frame(width: 640, height: 600)
    }
}

// MARK: - General

struct GeneralSettings: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var trusted = AccessibilityService.isTrusted
    @State private var iconHidden = false
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            if !settings.hasCompletedOnboarding {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Welcome to Grammable 👋").font(.title3.bold())
                        Text("Select text in any app and click the **G** button, or press **\(HotKey.defaultDisplay)**. Grammable uses AI you already have — Claude Code, Codex, Gemini CLI, Ollama or Apple Intelligence. No account, no subscription.")
                            .foregroundStyle(.secondary)
                        Text("1. Allow Accessibility below.  2. Pick your AI in **AI Backends**.  3. Select some text and try it.")
                            .font(.callout)
                        Button("Got it") { settings.hasCompletedOnboarding = true }
                    }
                    .padding(.vertical, 4)
                }
            }

            if iconHidden {
                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "menubar.rectangle").font(.title2).foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("The Grammable menu bar icon is hidden behind the notch").font(.headline)
                            Text("Your menu bar is full, so macOS hides the newest icons behind the camera. Grammable still works: select text for the G button, or press \(HotKey.defaultDisplay). To see the icon, quit some menu bar apps or hold ⌘ and drag icons off the menu bar. Open Grammable again any time to reach these settings.")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            Section("Permission") {
                HStack {
                    Image(systemName: trusted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                        .foregroundStyle(trusted ? .green : .orange).font(.title2)
                    VStack(alignment: .leading) {
                        Text(trusted ? "Accessibility access granted" : "Accessibility access needed")
                            .font(.headline)
                        Text("Used only to read the text you select and paste the result back. Nothing is logged or stored.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !trusted {
                        Text("Already enabled but not working? Remove Grammable from the list with “–”, then add it again.")
                            .font(.caption2).foregroundStyle(.secondary).frame(maxWidth: 160)
                        Button("Grant Access…") {
                            AccessibilityService.requestTrust()
                            AccessibilityService.openAccessibilitySettings()
                        }
                    }
                }
            }

            Section("Behavior") {
                Toggle("Enable Grammable", isOn: $settings.isEnabled)
                Toggle("Show the G button when I select text", isOn: $settings.popupOnSelection)
                    .disabled(!settings.isEnabled)
                HStack {
                    Text("Minimum selection: \(settings.minSelectionLength) characters")
                    Spacer()
                    Stepper("Minimum selection", value: $settings.minSelectionLength, in: 1...200).labelsHidden()
                }
                SettingRow("Menu bar icon") {
                    Text("Can't see it? A full menu bar hides icons behind the notch. Hold ⌘ and drag icons to make room, or open Grammable again to reach Settings.")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 330, alignment: .trailing)
                }
                SettingRow("Keyboard shortcut") {
                    Text(HotKey.defaultDisplay).font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
                }
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        do {
                            try LoginItem.setEnabled(newValue)
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                        }
                        launchAtLogin = LoginItem.isEnabled
                    }
                ))
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }
        }
        .groupedFormStyle()
        .onReceive(timer) { _ in
            trusted = AccessibilityService.isTrusted
            iconHidden = AppDelegate.isStatusItemHidden
        }
    }
}

// MARK: - Backends

struct BackendSettings: View {
    @ObservedObject private var settings = AppSettings.shared
    @StateObject private var model = BackendStatusModel()
    @StateObject private var offline = OfflineAISetupModel()
    private let offlineTimer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                OfflineAISetupView(model: offline) { model.refresh() }
            }

            Section {
                Picker("Default AI", selection: $settings.defaultBackend) {
                    ForEach(BackendID.allCases) { id in
                        HStack {
                            Text(id.displayName)
                            if model.statuses[id]?.isAvailable == true { Text("✓") }
                        }
                        .tag(id)
                    }
                }
                Text("Presets can override this — e.g. on-device for grammar, Claude for tone. Without any AI, grammar and spelling fixes use the macOS spell checker. Grammable has no servers and no subscription.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            ForEach(BackendID.allCases) { id in
                Section {
                    backendRow(id)
                }
            }
        }
        .groupedFormStyle()
        .toolbar {
            Button { model.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
        }
        .onAppear { model.refresh(); offline.refresh() }
        .onReceive(offlineTimer) { _ in offline.refresh() }
    }

    @ViewBuilder
    private func backendRow(_ id: BackendID) -> some View {
        let status = model.statuses[id]
        HStack(alignment: .firstTextBaseline) {
            Circle()
                .fill(status == nil ? Color.gray : (status!.isAvailable ? Color.green : Color.orange))
                .frame(width: 8, height: 8)
            Text(id.displayName).font(.headline)
            PrivacyBadge(backend: id)
            Spacer()
            if model.testing.contains(id) {
                ProgressView().controlSize(.small)
            } else {
                Button("Test") { model.test(id) }.disabled(status?.isAvailable != true)
            }
            Link(destination: id.setupURL) { Image(systemName: "questionmark.circle") }
        }
        VStack(alignment: .leading, spacing: 3) {
            Text(status?.detail ?? "Checking…").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Text(id.privacyNote).font(.caption2).foregroundStyle(.tertiary)
        }

        if id.executableName != nil {
            TextField("Path", text: Binding(
                get: { settings.path(for: id) }, set: { settings.setPath($0, for: id) }),
                prompt: Text("Auto-detect"))
        }
        if id == .ollama {
            TextField("Server", text: $settings.ollamaURL, prompt: Text("http://localhost:11434"))
        }
        if id == .openAICompatible {
            TextField("Server", text: $settings.openAIBaseURL, prompt: Text("http://localhost:1234/v1"))
        }
        if id != .apple && id != .builtIn {
            TextField("Model", text: Binding(
                get: { settings.model(for: id) }, set: { settings.setModel($0, for: id) }),
                prompt: Text(modelPlaceholder(id)))
        }
        if let test = model.testResult[id] {
            Text(test).font(.caption).foregroundStyle(test.hasPrefix("✓") ? .green : .red).textSelection(.enabled)
        }
    }

    private func modelPlaceholder(_ id: BackendID) -> String {
        switch id {
        case .claude: return "Default (e.g. haiku, sonnet)"
        case .codex: return "Default (e.g. gpt-5-mini)"
        case .gemini: return "Default (e.g. gemini-2.5-flash)"
        case .ollama: return "First installed model"
        case .openAICompatible: return "First loaded model"
        case .apple, .builtIn: return ""
        }
    }
}

// MARK: - Presets

struct PresetSettings: View {
    @State private var presets: [Preset] = []
    @State private var errors: [String] = []
    @State private var newName = ""
    @ObservedObject private var settings = AppSettings.shared
    private let store = PresetStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Presets are simple Markdown files in **\(abbreviated(store.directory.path))**. Edit them in any text editor, share them on GitHub, and they appear in the menu automatically.")
                .font(.callout).foregroundStyle(.secondary)

            List {
                ForEach(presets) { preset in
                    HStack {
                        Image(systemName: preset.icon).frame(width: 20).foregroundStyle(Brand.gradient)
                        VStack(alignment: .leading) {
                            Text(preset.name)
                            Text("\(preset.mode == .fix ? "Accept / reject changes" : "Before / after") · \(GrammableEngine.resolveBackend(for: preset, default: settings.defaultBackend).displayName)\(preset.isBuiltIn ? " · built-in" : BuiltInPresets.all.contains { $0.id == preset.id } ? " · customized" : "")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(preset.isBuiltIn ? "Customize" : "Edit") { edit(preset) }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))

            ForEach(errors, id: \.self) { Text($0).font(.caption).foregroundStyle(.red) }

            HStack {
                TextField("New preset name", text: $newName).frame(maxWidth: 200)
                Button("Create") { create() }.disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
                Button("Open Folder") { openFolder() }
                Button("Reload") { reload() }
                Link("Browse community presets", destination: Brand.presetsURL)
            }
        }
        .padding()
        .onAppear(perform: reload)
    }

    private func abbreviated(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    private func reload() {
        let result = store.load()
        presets = result.presets
        errors = result.errors
    }

    private func openFolder() {
        if let dir = try? store.ensureDirectory() { NSWorkspace.shared.open(dir) }
    }

    private func edit(_ preset: Preset) {
        let url = preset.isBuiltIn ? (try? store.exportBuiltIn(preset)) : preset.fileURL
        if let url { NSWorkspace.shared.open(url) }
        reload()
    }

    private func create() {
        if let url = try? store.createPreset(named: newName) {
            NSWorkspace.shared.open(url)
            newName = ""
            reload()
        }
    }
}

// MARK: - Privacy

struct PrivacySettings: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Grammable has no servers, no analytics and no account.", systemImage: "lock.shield")
                    Label("Password fields are never read.", systemImage: "key.slash")
                    Label("Your text goes only to the AI backend you choose: on-device (Ollama, LM Studio, Apple) or the agent CLI you signed in to (Claude Code, Codex, Gemini).", systemImage: "arrow.triangle.branch")
                    Label("Your clipboard is restored after copying or pasting.", systemImage: "doc.on.clipboard")
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            Text("Never show the G button in these apps").font(.headline)
            List(selection: $selection) {
                ForEach(settings.excludedBundleIDs, id: \.self) { id in
                    HStack {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 16, height: 16)
                            Text(FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
                        } else {
                            Image(systemName: "app.dashed").frame(width: 16).foregroundStyle(.tertiary)
                            Text(Self.knownNames[id] ?? id)
                            Text("not installed").font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text(id).font(.caption).foregroundStyle(.tertiary)
                    }
                    .tag(id)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))

            HStack {
                Menu("Add Running App") {
                    ForEach(runningApps, id: \.bundleIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "") {
                            if let id = app.bundleIdentifier, !settings.excludedBundleIDs.contains(id) {
                                settings.excludedBundleIDs.append(id)
                            }
                        }
                    }
                }
                .fixedSize()
                Button("Remove") {
                    if let selection { settings.excludedBundleIDs.removeAll { $0 == selection } }
                    selection = nil
                }
                .disabled(selection == nil)
                Spacer()
                Button("Restore Defaults") { settings.excludedBundleIDs = AppSettings.defaultExcludedBundleIDs }
            }
        }
        .padding()
    }

    static let knownNames: [String: String] = [
        "com.googlecode.iterm2": "iTerm2", "com.mitchellh.ghostty": "Ghostty", "dev.warp.Warp-Stable": "Warp",
        "net.kovidgoyal.kitty": "kitty", "io.alacritty": "Alacritty", "com.1password.1password": "1Password",
        "com.agilebits.onepassword7": "1Password 7", "com.bitwarden.desktop": "Bitwarden",
        "com.apple.Passwords": "Passwords", "com.apple.keychainaccess": "Keychain Access",
    ]

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }
}

// MARK: - About

struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("Grammable").font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(Brand.gradient)
            Text("Version \(Brand.version)").foregroundStyle(.secondary)
            Text("Free, open-source AI grammar checker & rewriter for macOS.\nNo subscription. No account. Uses the AI you already have.")
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Link("GitHub", destination: Brand.repositoryURL)
                Link("Report an issue", destination: Brand.issuesURL)
                Link("Check for updates", destination: Brand.releasesURL)
            }
            Link(destination: Brand.sponsorURL) {
                Label("Buy me a coffee on Ko-fi", systemImage: "cup.and.saucer.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
            Spacer()
            Text("Copyright © 2026 Udaya Lakmal · Licensed under GPL-3.0")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(30)
        .frame(maxWidth: .infinity)
    }
}
