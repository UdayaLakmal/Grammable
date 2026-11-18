// Grammable — Copyright (C) 2026 Udaya Lakmal — GPL-3.0-or-later

import Foundation

/// Helps set up a free, fully offline AI: Ollama plus a small model.
/// Grammable never bundles a model; it asks Ollama to download one the user picks.
public enum OllamaSetup {

    /// Small models that are good enough for grammar, tone and rewrites.
    public struct ModelChoice: Identifiable, Hashable, Sendable {
        public let id: String
        public let name: String
        public let size: String
        public let note: String
    }

    public static let recommendedModels: [ModelChoice] = [
        ModelChoice(id: "llama3.2:3b", name: "Llama 3.2 3B", size: "2.0 GB", note: "Better writing. Recommended."),
        ModelChoice(id: "llama3.2:1b", name: "Llama 3.2 1B", size: "1.3 GB", note: "Fastest. Good for older or Intel Macs."),
    ]

    public static let downloadURL = URL(string: "https://ollama.com/download/mac")!

    public static let appLocations = [
        "/Applications/Ollama.app",
        NSHomeDirectory() + "/Applications/Ollama.app",
    ]

    /// Path to Ollama.app, if installed.
    public static var appPath: String? {
        appLocations.first { FileManager.default.fileExists(atPath: $0) }
    }

    /// Path to the `ollama` command (Homebrew or the app's bundled CLI), if installed.
    public static var cliPath: String? {
        ShellEnvironment.shared.findExecutable("ollama")
    }

    public static var isInstalled: Bool { appPath != nil || cliPath != nil }

    /// Installed model names, or nil when Ollama isn't running.
    public static func installedModels(baseURL: String) async -> [String]? {
        try? await OllamaBackend(configuration: BackendConfiguration(ollamaURL: baseURL)).installedModels()
    }

    /// Starts Ollama when only the command-line version is installed (the app starts itself when opened).
    public static func startServer() {
        guard let cli = cliPath else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cli)
        process.arguments = ["serve"]
        process.environment = ShellEnvironment.shared.environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    /// Downloads a model through Ollama's API, reporting progress from 0 to 1.
    public static func pull(
        model: String,
        baseURL: String,
        progress: @escaping @Sendable (_ fraction: Double, _ status: String) -> Void
    ) async throws {
        var trimmed = baseURL.trimmingCharacters(in: .whitespaces)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let url = URL(string: trimmed + "/api/pull") else {
            throw BackendError.failed("Invalid Ollama URL: \(baseURL)")
        }
        var request = URLRequest(url: url, timeoutInterval: 60 * 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "stream": true])

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw BackendError.failed("Ollama returned HTTP \(http.statusCode) while downloading \(model).")
        }

        // Each line is a JSON status. Downloads report per-layer totals; sum them for one progress bar.
        var totals: [String: Double] = [:]
        var completed: [String: Double] = [:]
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let error = json["error"] as? String { throw BackendError.failed("Ollama: \(error)") }
            let status = json["status"] as? String ?? ""
            if let digest = json["digest"] as? String, let total = json["total"] as? Double, total > 0 {
                totals[digest] = total
                completed[digest] = json["completed"] as? Double ?? completed[digest] ?? 0
            }
            let all = totals.values.reduce(0, +)
            let done = completed.values.reduce(0, +)
            if status == "success" {
                progress(1, "Done")
                return
            }
            progress(all > 0 ? min(done / all, 1) : 0, status)
        }
        throw BackendError.failed("The download from Ollama stopped before it finished. Try again.")
    }
}
