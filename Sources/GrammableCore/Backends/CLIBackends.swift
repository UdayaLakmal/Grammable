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

// MARK: - Antigravity CLI

/// Google Antigravity's command-line tool, `agy -p` (print mode) on the user's own account.
/// Needs the `agy` command-line tool; the Antigravity desktop app on its own is not enough.
public struct AntigravityBackend: CLIBackend {
    public let id = BackendID.antigravity
    public let configuration: BackendConfiguration

    public init(configuration: BackendConfiguration) { self.configuration = configuration }

    public func complete(_ request: AIRequest) async throws -> String {
        let exe = try requireExecutable()
        var args = [
            "-p", PromptBuilder.combinedPrompt(instructions: request.instructions, text: request.text),
            "--output-format", "text",
            "--print-timeout", "\(Int(configuration.timeout))s",
        ]
        if let model = configuration.model(for: id, override: request.model) { args += ["--model", model] }

        let result = try await CLIRunner.run(executable: exe, arguments: args, timeout: configuration.timeout)
        let output = CLIRunner.stripTerminalCodes(result.stdout)
        if result.exitCode != 0 {
            if (result.stderr + result.stdout).lowercased().contains("authentication required") {
                throw BackendError.unavailable("Antigravity CLI isn't signed in. Run `agy` once in Terminal to sign in.")
            }
            throw CLIRunner.failure(result, tool: "agy")
        }
        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Some agy versions print nothing when they aren't attached to a terminal.
            throw BackendError.failed("Antigravity CLI finished without printing an answer. Update it with `agy update`, or pick another backend.")
        }
        return output
    }
}

// MARK: - Devin CLI

/// Cognition's Devin command-line tool in print mode (`devin -p`), on the user's own account.
/// Devin has no switch to turn tools off, so it runs with `--permission-mode auto` (read-only tools
/// only) in Grammable's empty working folder, and the prompt asks for text only.
public struct DevinBackend: CLIBackend {
    public let id = BackendID.devin
    public let configuration: BackendConfiguration

    public init(configuration: BackendConfiguration) { self.configuration = configuration }

    public func checkAvailability() async -> BackendStatus {
        guard let path = executablePath else { return .missing("Not found. \(id.setupHint)") }
        // Signing in is a separate step; say so instead of failing on first use.
        if let status = try? await CLIRunner.run(executable: path, arguments: ["auth", "status"], timeout: 8),
           (status.stdout + status.stderr).contains("Not logged in") {
            return .missing("Installed at \(path), but not signed in. Run `devin auth login` once in Terminal.")
        }
        return .available(path)
    }

    public func complete(_ request: AIRequest) async throws -> String {
        let exe = try requireExecutable()
        let promptFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("grammable-devin-\(UUID().uuidString).txt")
        try Data(PromptBuilder.combinedPrompt(instructions: request.instructions, text: request.text).utf8)
            .write(to: promptFile, options: .atomic)
        defer { try? FileManager.default.removeItem(at: promptFile) }

        var args = [
            "-p",
            "--prompt-file", promptFile.path,
            "--permission-mode", "auto",
            "--respect-workspace-trust", "false",
            "--process-model", "in-process",
            "--verbosity", "0",
        ]
        if let model = configuration.model(for: id, override: request.model) { args += ["--model", model] }

        let result = try await CLIRunner.run(executable: exe, arguments: args, timeout: configuration.timeout)
        if result.exitCode != 0 {
            let message = (result.stderr + result.stdout).lowercased()
            if message.contains("login") || message.contains("not logged in") {
                throw BackendError.unavailable("Devin CLI isn't signed in. Run `devin auth login` once in Terminal.")
            }
            throw CLIRunner.failure(result, tool: "devin")
        }
        return CLIRunner.stripTerminalCodes(result.stdout)
    }
}
