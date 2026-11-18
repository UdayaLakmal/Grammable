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
///
/// Output is streamed as JSON events and the answer is taken as soon as the agent's response step is
/// done. `agy` sometimes keeps a finished turn open for a long time, and killing it mid-turn makes the
/// next run stall, so it is left to exit on its own (its own time limit is a little shorter than ours).
public struct AntigravityBackend: CLIBackend {
    public let id = BackendID.antigravity
    public let configuration: BackendConfiguration

    public init(configuration: BackendConfiguration) { self.configuration = configuration }

    public func complete(_ request: AIRequest) async throws -> String {
        let exe = try requireExecutable()
        var args = [
            "-p", PromptBuilder.combinedPrompt(instructions: request.instructions, text: request.text),
            "--output-format", "stream-json",
            "--print-timeout", "\(max(10, Int(configuration.timeout) - 5))s",
            "--disable-slash-commands",
            // No `--sandbox`: it made runs fail at random. Tools still need approval, which print mode
            // can't give, so the agent can't act on anything; it can only answer.
        ]
        if let model = configuration.model(for: id, override: request.model) { args += ["--model", model] }

        let parser = AntigravityStreamParser()
        let answer: String
        do {
            answer = try await CLIRunner.runStreaming(
                executable: exe, arguments: args, timeout: configuration.timeout,
                handle: { parser.handle($0) })
        } catch BackendError.failed(let message) where message.lowercased().contains("authentication required") {
            throw BackendError.unavailable("Antigravity CLI isn't signed in. Run `agy` once in Terminal to sign in.")
        }
        if answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw BackendError.emptyResponse }
        return answer
    }
}

/// Reads `agy --output-format stream-json` events.
final class AntigravityStreamParser: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""

    func handle(_ line: String) -> CLIRunner.LineDecision {
        guard let data = line.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .keepReading }
        lock.lock(); defer { lock.unlock() }

        switch event["event"] as? String {
        case "step_update":
            guard let step = event["step_update"] as? [String: Any] else { return .keepReading }
            let type = step["step_type"] as? String ?? ""
            let state = step["state"] as? String ?? ""
            if type == "agent_response" {
                text += step["text_delta"] as? String ?? ""
                if state == "DONE" {
                    // A response step can finish with no text (thinking only); wait for the real answer.
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { text = ""; return .keepReading }
                    return .finished(text)
                }
            } else if type == "error_message" {
                let message = (step["text"] as? String) ?? (step["text_delta"] as? String) ?? (step["error"] as? String)
                let detail = message.map { ": \($0)" } ?? ""
                return .failed(.failed("Antigravity reported an error\(detail). Try again, or pick another backend."))
            }
        case "result":
            let result = event["result"] as? [String: Any] ?? [:]
            if let response = result["response"] as? String, !response.isEmpty { return .finished(response) }
            if !text.isEmpty { return .finished(text) }
            let status = result["status"] as? String ?? "unknown"
            return .failed(.failed("Antigravity finished without an answer (status \(status))."))
        case "error":
            let message = (event["error"] as? [String: Any])?["message"] as? String
                ?? (event["error"] as? String) ?? "unknown error"
            if message.lowercased().contains("auth") {
                return .failed(.unavailable("Antigravity CLI isn't signed in. Run `agy` once in Terminal to sign in."))
            }
            return .failed(.failed("Antigravity: \(message)"))
        default:
            break
        }
        return .keepReading
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
