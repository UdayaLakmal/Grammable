// Grammable — Copyright (C) 2026 Udaya Lakmal — GPL-3.0-or-later

import Foundation

/// Shared logic for agent CLIs that are already installed and signed in on this Mac.
/// Grammable only *runs* them — it never stores keys or tokens.
protocol CLIBackend: AIBackend {
    var configuration: BackendConfiguration { get }
}

extension CLIBackend {
    var executablePath: String? {
        guard let name = id.executableName else { return nil }
        return ShellEnvironment.shared.findExecutable(name, customPath: configuration.executablePaths[id])
    }

    func requireExecutable() throws -> String {
        guard let path = executablePath else { throw BackendError.notInstalled(id) }
        return path
    }

    public func checkAvailability() async -> BackendStatus {
        if let path = executablePath { return .available(path) }
        return .missing("Not found. \(id.setupHint)")
    }
}

// MARK: - Claude Code

/// `claude -p` with tools, MCP servers, settings and session history disabled:
/// a plain, fast, single-turn text completion on the user's own Claude plan.
public struct ClaudeCodeBackend: CLIBackend {
    public let id = BackendID.claude
    public let configuration: BackendConfiguration

    public init(configuration: BackendConfiguration) { self.configuration = configuration }

    public func complete(_ request: AIRequest) async throws -> String {
        let exe = try requireExecutable()
        var args = [
            "-p",
            "--output-format", "text",
            "--system-prompt", PromptBuilder.systemPrompt,
            "--tools", "",
            "--strict-mcp-config",
            "--setting-sources", "",
            "--no-session-persistence",
        ]
        if let model = configuration.model(for: id, override: request.model) { args += ["--model", model] }

        let result = try await CLIRunner.run(
            executable: exe, arguments: args,
            stdin: PromptBuilder.userPrompt(instructions: request.instructions, text: request.text),
            timeout: configuration.timeout
        )
        guard result.exitCode == 0 else { throw CLIRunner.failure(result, tool: "claude") }
        return result.stdout
    }
}

// MARK: - Codex CLI

/// `codex exec` in a read-only sandbox; the final answer is read from `--output-last-message`.
public struct CodexBackend: CLIBackend {
    public let id = BackendID.codex
    public let configuration: BackendConfiguration

    public init(configuration: BackendConfiguration) { self.configuration = configuration }

    public func complete(_ request: AIRequest) async throws -> String {
        let exe = try requireExecutable()
        let outFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("grammable-codex-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: outFile) }

        var args = [
            "exec",
            "--skip-git-repo-check",
            "--sandbox", "read-only",
            "--color", "never",
            "--output-last-message", outFile.path,
        ]
        if let model = configuration.model(for: id, override: request.model) { args += ["--model", model] }
        args.append("-") // read the prompt from stdin

        let result = try await CLIRunner.run(
            executable: exe, arguments: args,
            stdin: PromptBuilder.combinedPrompt(instructions: request.instructions, text: request.text),
            timeout: configuration.timeout
        )
        guard result.exitCode == 0 else { throw CLIRunner.failure(result, tool: "codex") }
        if let last = try? String(contentsOf: outFile, encoding: .utf8),
           !last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return last
        }
        return result.stdout
    }
}

// MARK: - Gemini CLI

/// `gemini -p` non-interactive mode on the user's own Google account.
public struct GeminiBackend: CLIBackend {
    public let id = BackendID.gemini
    public let configuration: BackendConfiguration

    public init(configuration: BackendConfiguration) { self.configuration = configuration }

    public func complete(_ request: AIRequest) async throws -> String {
        let exe = try requireExecutable()
        var args: [String] = []
        if let model = configuration.model(for: id, override: request.model) { args += ["--model", model] }
        args += ["--prompt", PromptBuilder.combinedPrompt(instructions: request.instructions, text: request.text)]

        let result = try await CLIRunner.run(executable: exe, arguments: args, timeout: configuration.timeout)
        guard result.exitCode == 0 else { throw CLIRunner.failure(result, tool: "gemini") }
        return result.stdout
    }
}
