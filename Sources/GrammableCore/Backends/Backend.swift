// Grammable — Copyright (C) 2026 Udaya Lakmal — GPL-3.0-or-later

import Foundation

/// Every engine Grammable can drive. All of them are things you already have
/// (or can install for free) — Grammable never ships its own model or server.
/// `builtIn` is the macOS spelling and grammar checker: no AI, fixes only, always available.
public enum BackendID: String, CaseIterable, Codable, Identifiable, Sendable {
    case claude
    case codex
    case gemini
    case ollama
    case openAICompatible = "openai-compatible"
    case apple
    case builtIn = "builtin"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex CLI"
        case .gemini: return "Gemini CLI"
        case .ollama: return "Ollama"
        case .openAICompatible: return "LM Studio / OpenAI-compatible"
        case .apple: return "Apple Intelligence (on-device)"
        case .builtIn: return "macOS Spelling & Grammar"
        }
    }

    public var shortName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .gemini: return "Gemini"
        case .ollama: return "Ollama"
        case .openAICompatible: return "Local server"
        case .apple: return "Apple"
        case .builtIn: return "macOS"
        }
    }

    /// `true` when the text never leaves this Mac.
    public var isOnDevice: Bool {
        switch self {
        case .ollama, .openAICompatible, .apple, .builtIn: return true
        case .claude, .codex, .gemini: return false
        }
    }

    /// `false` for the built-in checker, which can fix spelling and grammar but not rewrite.
    public var canRewrite: Bool { self != .builtIn }

    /// Command-line executable name, for CLI-based backends.
    public var executableName: String? {
        switch self {
        case .claude: return "claude"
        case .codex: return "codex"
        case .gemini: return "gemini"
        default: return nil
        }
    }

    public var privacyNote: String {
        switch self {
        case .claude: return "Runs your installed Claude Code CLI. Text is sent to Anthropic under your own Claude account."
        case .codex: return "Runs your installed Codex CLI. Text is sent to OpenAI under your own ChatGPT / OpenAI account."
        case .gemini: return "Runs your installed Gemini CLI. Text is sent to Google under your own Google account."
        case .ollama: return "Runs a model on this Mac through Ollama. Fully offline."
        case .openAICompatible: return "Talks to a local OpenAI-compatible server such as LM Studio, Jan or llama.cpp. Offline when the server is local."
        case .apple: return "Uses Apple's on-device foundation model (macOS 26+, Apple Intelligence enabled). Fully offline."
        case .builtIn: return "Uses the spelling and grammar checker built into macOS. Fully offline, nothing to install. Fixes spelling and grammar only; rewrites and tone changes need an AI."
        }
    }

    public var setupHint: String {
        switch self {
        case .claude: return "Install: npm install -g @anthropic-ai/claude-code — then run `claude` once to sign in."
        case .codex: return "Install: npm install -g @openai/codex (or brew install codex) — then run `codex` once to sign in."
        case .gemini: return "Install: npm install -g @google/gemini-cli (or brew install gemini-cli) — then run `gemini` once to sign in."
        case .ollama: return "Install from ollama.com (or brew install ollama), then: ollama pull llama3.2"
        case .openAICompatible: return "Start the local server in LM Studio (Developer → Start Server), Jan or llama.cpp."
        case .apple: return "Requires macOS 26 or later on Apple silicon with Apple Intelligence turned on."
        case .builtIn: return "Built into macOS. Nothing to install."
        }
    }

    public var setupURL: URL {
        switch self {
        case .claude: return URL(string: "https://docs.anthropic.com/en/docs/claude-code")!
        case .codex: return URL(string: "https://github.com/openai/codex")!
        case .gemini: return URL(string: "https://github.com/google-gemini/gemini-cli")!
        case .ollama: return URL(string: "https://ollama.com")!
        case .openAICompatible: return URL(string: "https://lmstudio.ai")!
        case .apple: return URL(string: "https://www.apple.com/apple-intelligence/")!
        case .builtIn: return URL(string: "https://github.com/UdayaLakmal/Grammable#ai-backends")!
        }
    }
}

/// User-tunable backend settings.
public struct BackendConfiguration: Sendable, Equatable {
    /// Custom executable paths for CLI backends (empty = auto-detect).
    public var executablePaths: [BackendID: String]
    /// Model per backend (empty = backend default).
    public var models: [BackendID: String]
    public var ollamaURL: String
    public var openAIBaseURL: String
    public var timeout: TimeInterval

    public init(
        executablePaths: [BackendID: String] = [:],
        models: [BackendID: String] = [:],
        ollamaURL: String = "http://localhost:11434",
        openAIBaseURL: String = "http://localhost:1234/v1",
        timeout: TimeInterval = 90
    ) {
        self.executablePaths = executablePaths
        self.models = models
        self.ollamaURL = ollamaURL
        self.openAIBaseURL = openAIBaseURL
        self.timeout = timeout
    }

    public func model(for id: BackendID, override: String? = nil) -> String? {
        if let override, !override.isEmpty { return override }
        if let m = models[id]?.trimmingCharacters(in: .whitespaces), !m.isEmpty { return m }
        return nil
    }
}

public enum BackendError: Error, LocalizedError, Equatable {
    case notInstalled(BackendID)
    case notReachable(BackendID, String)
    case unavailable(String)
    case timedOut(TimeInterval)
    case failed(String)
    case emptyResponse
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .notInstalled(let id):
            return "\(id.displayName) was not found on this Mac. \(id.setupHint)"
        case .notReachable(let id, let detail):
            return "Could not reach \(id.displayName). \(detail)"
        case .unavailable(let reason):
            return reason
        case .timedOut(let seconds):
            return "The AI did not answer within \(Int(seconds)) seconds. Try again or pick a faster backend."
        case .failed(let message):
            return message
        case .emptyResponse:
            return "The AI returned an empty answer. Try again."
        case .cancelled:
            return "Cancelled."
        }
    }
}

extension BackendError {
    /// The AI isn't installed, running or usable on this Mac (as opposed to failing mid-request).
    public var meansNotSetUp: Bool {
        switch self {
        case .notInstalled, .notReachable, .unavailable: return true
        default: return false
        }
    }
}

/// A single request: instruction + text.
public struct AIRequest: Sendable {
    public var instructions: String
    public var text: String
    public var model: String?

    public init(instructions: String, text: String, model: String? = nil) {
        self.instructions = instructions
        self.text = text
        self.model = model
    }
}

public protocol AIBackend: Sendable {
    var id: BackendID { get }
    /// Fast check used to show status in the UI. Must not prompt the user.
    func checkAvailability() async -> BackendStatus
    /// Returns the raw model output (not yet cleaned).
    func complete(_ request: AIRequest) async throws -> String
}

public struct BackendStatus: Sendable, Equatable {
    public var isAvailable: Bool
    /// Path, URL or version info for display.
    public var detail: String

    public static func available(_ detail: String) -> BackendStatus { .init(isAvailable: true, detail: detail) }
    public static func missing(_ detail: String) -> BackendStatus { .init(isAvailable: false, detail: detail) }
}

public enum BackendFactory {
    public static func make(_ id: BackendID, configuration: BackendConfiguration) -> AIBackend {
        switch id {
        case .claude: return ClaudeCodeBackend(configuration: configuration)
        case .codex: return CodexBackend(configuration: configuration)
        case .gemini: return GeminiBackend(configuration: configuration)
        case .ollama: return OllamaBackend(configuration: configuration)
        case .openAICompatible: return OpenAICompatibleBackend(configuration: configuration)
        case .apple: return AppleIntelligenceBackend()
        case .builtIn: return MacSpellCheckerBackend()
        }
    }
}
