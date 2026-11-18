// Grammable — Copyright (C) 2026 Udaya Lakmal — GPL-3.0-or-later

import Foundation
import GrammableCore

/// User preferences, persisted in UserDefaults.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let isEnabled = "isEnabled"
        static let popupOnSelection = "popupOnSelection"
        static let minSelectionLength = "minSelectionLength"
        static let defaultBackend = "defaultBackend"
        static let executablePaths = "executablePaths"
        static let models = "models"
        static let ollamaURL = "ollamaURL"
        static let openAIBaseURL = "openAIBaseURL"
        static let timeout = "timeout"
        static let excludedBundleIDs = "excludedBundleIDs"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let hasLaunchedBefore = "hasLaunchedBefore"
    }

    static let defaultExcludedBundleIDs = ["com.apple.Terminal", "com.apple.keychainaccess"]

    /// Master switch from the menu bar.
    @Published var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: Key.isEnabled) } }
    /// Show the floating button automatically after selecting text.
    @Published var popupOnSelection: Bool { didSet { defaults.set(popupOnSelection, forKey: Key.popupOnSelection) } }
    @Published var minSelectionLength: Int { didSet { defaults.set(minSelectionLength, forKey: Key.minSelectionLength) } }
    @Published var defaultBackend: BackendID { didSet { defaults.set(defaultBackend.rawValue, forKey: Key.defaultBackend) } }
    @Published var executablePaths: [String: String] { didSet { defaults.set(executablePaths, forKey: Key.executablePaths) } }
    @Published var models: [String: String] { didSet { defaults.set(models, forKey: Key.models) } }
    @Published var ollamaURL: String { didSet { defaults.set(ollamaURL, forKey: Key.ollamaURL) } }
    @Published var openAIBaseURL: String { didSet { defaults.set(openAIBaseURL, forKey: Key.openAIBaseURL) } }
    @Published var timeout: Double { didSet { defaults.set(timeout, forKey: Key.timeout) } }
    @Published var excludedBundleIDs: [String] { didSet { defaults.set(excludedBundleIDs, forKey: Key.excludedBundleIDs) } }
    @Published var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) } }

    private init() {
        defaults.register(defaults: [
            Key.isEnabled: true,
            Key.popupOnSelection: true,
            Key.minSelectionLength: 3,
            Key.ollamaURL: "http://localhost:11434",
            Key.openAIBaseURL: "http://localhost:1234/v1",
            Key.timeout: 90.0,
            Key.excludedBundleIDs: Self.defaultExcludedBundleIDs,
        ])
        isEnabled = defaults.bool(forKey: Key.isEnabled)
        popupOnSelection = defaults.bool(forKey: Key.popupOnSelection)
        minSelectionLength = max(1, defaults.integer(forKey: Key.minSelectionLength))
        defaultBackend = defaults.string(forKey: Key.defaultBackend).flatMap(BackendID.init(rawValue:)) ?? .claude
        executablePaths = defaults.dictionary(forKey: Key.executablePaths) as? [String: String] ?? [:]
        models = defaults.dictionary(forKey: Key.models) as? [String: String] ?? [:]
        ollamaURL = defaults.string(forKey: Key.ollamaURL) ?? "http://localhost:11434"
        openAIBaseURL = defaults.string(forKey: Key.openAIBaseURL) ?? "http://localhost:1234/v1"
        timeout = defaults.double(forKey: Key.timeout)
        excludedBundleIDs = defaults.stringArray(forKey: Key.excludedBundleIDs) ?? Self.defaultExcludedBundleIDs
        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
    }

    /// False only on the very first launch. Settings opens automatically just that once.
    var hasLaunchedBefore: Bool {
        get { defaults.bool(forKey: Key.hasLaunchedBefore) }
        set { defaults.set(newValue, forKey: Key.hasLaunchedBefore) }
    }

    /// Whether the user has explicitly chosen a default backend yet.
    var hasChosenBackend: Bool { defaults.string(forKey: Key.defaultBackend) != nil }

    var backendConfiguration: BackendConfiguration {
        BackendConfiguration(
            executablePaths: Dictionary(uniqueKeysWithValues: executablePaths.compactMap { key, value in
                BackendID(rawValue: key).map { ($0, value) }
            }),
            models: Dictionary(uniqueKeysWithValues: models.compactMap { key, value in
                BackendID(rawValue: key).map { ($0, value) }
            }),
            ollamaURL: ollamaURL,
            openAIBaseURL: openAIBaseURL,
            timeout: max(10, timeout)
        )
    }

    func model(for id: BackendID) -> String { models[id.rawValue] ?? "" }
    func setModel(_ value: String, for id: BackendID) { models[id.rawValue] = value }
    func path(for id: BackendID) -> String { executablePaths[id.rawValue] ?? "" }
    func setPath(_ value: String, for id: BackendID) { executablePaths[id.rawValue] = value }
}
