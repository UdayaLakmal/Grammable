// Grammable — Copyright (C) 2026 Udaya Lakmal — GPL-3.0-or-later

import Foundation

/// How the result of a preset is reviewed.
public enum PresetMode: String, Codable, CaseIterable, Sendable {
    /// Small corrections. Shown as individual changes the user can accept or reject.
    case fix
    /// Whole-text transformation (tone, format, length). Shown as before / after.
    case rewrite
}

/// A writing action, e.g. "Fix Grammar & Spelling" or "Make Professional".
///
/// Presets are plain Markdown files with a small front-matter header so they are
/// easy to write, version and share on GitHub:
///
/// ```markdown
/// ---
/// name: Professional Email
/// icon: briefcase
/// mode: rewrite
/// backend: claude      # optional: claude | codex | gemini | ollama | openai-compatible | apple
/// model: sonnet        # optional, backend specific
/// order: 20            # optional, sort position in the menu
/// ---
/// Rewrite the text in a clear, polite and professional tone.
/// ```
public struct Preset: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    /// SF Symbol name shown in the menu.
    public var icon: String
    public var mode: PresetMode
    /// Optional backend override (raw value of `BackendID`). `nil` = use the default backend.
    public var backend: String?
    /// Optional model override for the chosen backend.
    public var model: String?
    public var order: Int
    /// The instruction sent to the AI.
    public var instructions: String
    public var isBuiltIn: Bool
    public var fileURL: URL?

    public init(
        id: String,
        name: String,
        icon: String = "wand.and.stars",
        mode: PresetMode = .rewrite,
        backend: String? = nil,
        model: String? = nil,
        order: Int = 100,
        instructions: String,
        isBuiltIn: Bool = false,
        fileURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.mode = mode
        self.backend = backend
        self.model = model
        self.order = order
        self.instructions = instructions
        self.isBuiltIn = isBuiltIn
        self.fileURL = fileURL
    }

    public var backendID: BackendID? {
        backend.flatMap { BackendID(rawValue: $0.lowercased()) }
    }
}
