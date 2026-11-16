// Grammable — Copyright (C) 2026 Udaya Lakmal — GPL-3.0-or-later

import Foundation

public enum PresetParserError: Error, LocalizedError, Equatable {
    case emptyInstructions(String)

    public var errorDescription: String? {
        switch self {
        case .emptyInstructions(let file):
            return "Preset “\(file)” has no instructions below the front matter."
        }
    }
}

/// Reads and writes preset Markdown files (`--- key: value --- body`).
/// Only a flat `key: value` subset of YAML is supported, which keeps presets
/// readable and the parser dependency-free.
public enum PresetParser {

    public static func parse(_ text: String, id: String, fileURL: URL? = nil) throws -> Preset {
        let (meta, body) = splitFrontMatter(text)
        let instructions = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instructions.isEmpty else {
            throw PresetParserError.emptyInstructions(fileURL?.lastPathComponent ?? id)
        }

        let name = meta["name"].flatMap { $0.isEmpty ? nil : $0 } ?? humanize(id)
        let mode = meta["mode"].flatMap { PresetMode(rawValue: $0.lowercased()) } ?? .rewrite
        let order = meta["order"].flatMap { Int($0) } ?? 100
        let icon = meta["icon"].flatMap { $0.isEmpty ? nil : $0 } ?? "wand.and.stars"
        let backend = meta["backend"].flatMap { $0.isEmpty || $0 == "default" ? nil : $0.lowercased() }
        let model = meta["model"].flatMap { $0.isEmpty ? nil : $0 }

        return Preset(
            id: id, name: name, icon: icon, mode: mode, backend: backend, model: model,
            order: order, instructions: instructions, isBuiltIn: false, fileURL: fileURL
        )
    }

    public static func serialize(_ preset: Preset) -> String {
        var lines = ["---", "name: \(preset.name)", "icon: \(preset.icon)", "mode: \(preset.mode.rawValue)"]
        if let backend = preset.backend { lines.append("backend: \(backend)") }
        if let model = preset.model { lines.append("model: \(model)") }
        lines.append("order: \(preset.order)")
        lines.append("---")
        lines.append(preset.instructions)
        return lines.joined(separator: "\n") + "\n"
    }

    /// Splits `---` front matter from the body. Text without front matter is all body.
    static func splitFrontMatter(_ text: String) -> ([String: String], String) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = normalized.components(separatedBy: "\n")
        // Skip a UTF-8 BOM and leading blank lines.
        while let first = lines.first, first.trimmingCharacters(in: .whitespaces.union(["\u{FEFF}"])).isEmpty {
            lines.removeFirst()
        }
        guard let first = lines.first,
              first.trimmingCharacters(in: .whitespaces.union(["\u{FEFF}"])) == "---" else {
            return ([:], normalized)
        }
        guard let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return ([:], normalized)
        }

        var meta: [String: String] = [:]
        for line in lines[1..<end] {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            var value = String(line[line.index(after: colon)...])
            // Strip trailing ` # comment` (only when preceded by whitespace, so "C#" survives).
            if let hash = value.range(of: " #") { value = String(value[..<hash.lowerBound]) }
            value = value.trimmingCharacters(in: .whitespaces)
            if value.count >= 2,
               let f = value.first, let l = value.last,
               (f == "\"" && l == "\"") || (f == "'" && l == "'") {
                value = String(value.dropFirst().dropLast())
            }
            if !key.isEmpty { meta[key] = value }
        }
        let body = lines[(end + 1)...].joined(separator: "\n")
        return (meta, body)
    }

    static func humanize(_ id: String) -> String {
        id.split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
