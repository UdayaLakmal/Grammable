// Grammable — Copyright (C) 2026 Udaya Lakmal — GPL-3.0-or-later

import Foundation

/// The outcome of running a preset on some text.
public struct EngineResult: Sendable {
    public let preset: Preset
    public let backend: BackendID
    public let original: String
    public let suggestion: String
    public let diff: TextDiff
    public let duration: TimeInterval

    public var isUnchanged: Bool { diff.changes.isEmpty }

    public init(preset: Preset, backend: BackendID, original: String, suggestion: String,
                diff: TextDiff, duration: TimeInterval) {
        self.preset = preset
        self.backend = backend
        self.original = original
        self.suggestion = suggestion
        self.diff = diff
        self.duration = duration
    }
}

/// Runs a preset against text with the right backend and post-processing.
public enum GrammableEngine {

    /// The backend a preset will use: its own override, otherwise the default.
    public static func resolveBackend(for preset: Preset, default defaultID: BackendID) -> BackendID {
        preset.backendID ?? defaultID
    }

    public static func run(
        preset: Preset,
        text: String,
        defaultBackend: BackendID,
        configuration: BackendConfiguration
    ) async throws -> EngineResult {
        let backendID = resolveBackend(for: preset, default: defaultBackend)
        let backend = BackendFactory.make(backendID, configuration: configuration)
        let start = Date()

        let raw = try await backend.complete(AIRequest(
            instructions: preset.instructions,
            text: text,
            model: preset.backendID == backendID ? preset.model : nil
        ))
        try Task.checkCancellation()

        let cleaned = PromptBuilder.clean(raw, original: text)
        guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BackendError.emptyResponse
        }
        return EngineResult(
            preset: preset,
            backend: backendID,
            original: text,
            suggestion: cleaned,
            diff: TextDiff(original: text, revised: cleaned),
            duration: Date().timeIntervalSince(start)
        )
    }
}
