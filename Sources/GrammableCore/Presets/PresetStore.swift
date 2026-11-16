// Grammable — Copyright (C) 2026 Udaya Lakmal — GPL-3.0-or-later

import Foundation

/// Loads built-in presets plus user presets from `~/.grammable/presets/*.md`.
public final class PresetStore {

    public struct LoadResult {
        public var presets: [Preset]
        public var errors: [String]
    }

    public let directory: URL
    private let fileManager: FileManager

    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grammable", isDirectory: true)
            .appendingPathComponent("presets", isDirectory: true)
    }

    public init(directory: URL = PresetStore.defaultDirectory, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    /// Built-in presets, overridden or extended by user files. Sorted by `order`, then name.
    public func load() -> LoadResult {
        var byID: [String: Preset] = [:]
        for preset in BuiltInPresets.all { byID[preset.id] = preset }

        var errors: [String] = []
        let files = (try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []

        for url in files where url.pathExtension.lowercased() == "md" {
            let id = url.deletingPathExtension().lastPathComponent.lowercased()
            if id == "readme" { continue }
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                var preset = try PresetParser.parse(text, id: id, fileURL: url)
                if let builtIn = byID[id], builtIn.isBuiltIn, preset.order == 100 {
                    preset.order = builtIn.order // keep menu position when overriding a built-in
                }
                byID[id] = preset
            } catch {
                errors.append(error.localizedDescription)
            }
        }

        let sorted = byID.values.sorted {
            $0.order != $1.order ? $0.order < $1.order
                : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return LoadResult(presets: sorted, errors: errors)
    }

    /// Creates the presets folder with a short README the first time.
    @discardableResult
    public func ensureDirectory() throws -> URL {
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let readme = directory.appendingPathComponent("README.md")
        if !fileManager.fileExists(atPath: readme.path) {
            try Self.folderReadme.write(to: readme, atomically: true, encoding: .utf8)
        }
        return directory
    }

    /// Writes a new preset file and returns its URL. Never overwrites an existing file.
    public func createPreset(named name: String) throws -> URL {
        try ensureDirectory()
        let base = Self.slug(name).isEmpty ? "my-preset" : Self.slug(name)
        var url = directory.appendingPathComponent("\(base).md")
        var n = 2
        while fileManager.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(base)-\(n).md")
            n += 1
        }
        let preset = Preset(
            id: url.deletingPathExtension().lastPathComponent,
            name: name, icon: "wand.and.stars", mode: .rewrite, order: 200,
            instructions: "Describe what Grammable should do with the selected text."
        )
        try PresetParser.serialize(preset).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Saves a copy of a built-in preset into the folder so the user can customise it.
    public func exportBuiltIn(_ preset: Preset) throws -> URL {
        try ensureDirectory()
        let url = directory.appendingPathComponent("\(preset.id).md")
        if !fileManager.fileExists(atPath: url.path) {
            try PresetParser.serialize(preset).write(to: url, atomically: true, encoding: .utf8)
        }
        return url
    }

    static func slug(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let lowered = s.lowercased().unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        return String(lowered)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
    }

    static let folderReadme = """
    # Grammable presets

    Every `.md` file in this folder becomes an action in the Grammable menu.
    A file named like a built-in preset (for example `fix-grammar.md`) replaces it.

    ```markdown
    ---
    name: Professional Email
    icon: briefcase          # any SF Symbol name
    mode: rewrite            # rewrite = before/after view, fix = accept/reject each change
    backend: claude          # optional: claude | codex | gemini | ollama | openai-compatible | apple
    model: sonnet            # optional, depends on the backend
    order: 20                # optional, position in the menu
    ---
    Rewrite the text in a clear, polite and professional tone.
    ```

    Share your best presets: https://github.com/UdayaLakmal/Grammable/tree/main/presets
    """
}
