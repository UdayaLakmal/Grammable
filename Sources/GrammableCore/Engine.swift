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
        configuration: BackendConfiguration,
        fallbackToBuiltIn: Bool = true
    ) async throws -> EngineResult {
        let backendID = resolveBackend(for: preset, default: defaultBackend)
        let start = Date()

        if !backendID.canRewrite && preset.mode != .fix {
            throw BackendError.unavailable(Self.needsAIMessage)
        }

        let raw: String
        var usedID = backendID
        do {
            raw = try await BackendFactory.make(backendID, configuration: configuration).complete(AIRequest(
                instructions: preset.instructions,
                text: text,
                model: preset.backendID == backendID ? preset.model : nil
            ))
        } catch let error as BackendError where fallbackToBuiltIn && preset.mode == .fix && error.meansNotSetUp {
            // No AI installed or running: grammar and spelling fixes still work with macOS's own checker.
            usedID = .builtIn
            raw = try await BackendFactory.make(.builtIn, configuration: configuration)
                .complete(AIRequest(instructions: preset.instructions, text: text))
        }
        try Task.checkCancellation()

        // The built-in checker returns the corrected text itself, with no model chatter to strip.
        let cleaned = usedID == .builtIn ? raw : PromptBuilder.clean(raw, original: text)
        guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BackendError.emptyResponse
        }
        return EngineResult(
            preset: preset,
            backend: usedID,
            original: text,
            suggestion: cleaned,
            diff: TextDiff(original: text, revised: cleaned),
            duration: Date().timeIntervalSince(start)
        )
    }

    public static let needsAIMessage =
        "The macOS spell checker can fix spelling and grammar, but rewrites and tone changes need an AI. " +
        "Set up a free offline AI (Ollama) in Settings › AI Backends, or use Claude Code, Codex or Gemini CLI."
}
