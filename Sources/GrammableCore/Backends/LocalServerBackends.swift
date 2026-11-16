// Grammable — Copyright (C) 2026 Udaya Lakmal — GPL-3.0-or-later

import Foundation

private func makeURL(_ base: String, _ path: String) -> URL? {
    var trimmed = base.trimmingCharacters(in: .whitespaces)
    while trimmed.hasSuffix("/") { trimmed.removeLast() }
    return URL(string: trimmed + path)
}

private func httpGetJSON(_ url: URL, timeout: TimeInterval) async throws -> Any {
    var req = URLRequest(url: url, timeoutInterval: timeout)
    req.httpMethod = "GET"
    let (data, response) = try await URLSession.shared.data(for: req)
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
        throw BackendError.failed("HTTP \(http.statusCode) from \(url.absoluteString)")
    }
    return try JSONSerialization.jsonObject(with: data)
}

private func httpPostJSON(_ url: URL, body: [String: Any], timeout: TimeInterval) async throws -> Any {
    var req = URLRequest(url: url, timeoutInterval: timeout)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await URLSession.shared.data(for: req)
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
        let message = String(decoding: data.prefix(500), as: UTF8.self)
        throw BackendError.failed("HTTP \(http.statusCode): \(message)")
    }
    return try JSONSerialization.jsonObject(with: data)
}

private func messages(_ request: AIRequest) -> [[String: String]] {
    [
        ["role": "system", "content": PromptBuilder.systemPrompt],
        ["role": "user", "content": PromptBuilder.userPrompt(instructions: request.instructions, text: request.text)],
    ]
}

private func mapURLError(_ error: Error, id: BackendID, base: String) -> Error {
    if error is CancellationError { return BackendError.cancelled }
    if let urlError = error as? URLError {
        switch urlError.code {
        case .cancelled: return BackendError.cancelled
        case .timedOut: return BackendError.timedOut(0)
        case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet:
            return BackendError.notReachable(id, "Is it running at \(base)? \(id.setupHint)")
        default: break
        }
    }
    return error
}

// MARK: - Ollama

/// Ollama's local REST API. Picks the first installed model when none is configured.
public struct OllamaBackend: AIBackend {
    public let id = BackendID.ollama
    let configuration: BackendConfiguration

    public init(configuration: BackendConfiguration) { self.configuration = configuration }

    public func installedModels() async throws -> [String] {
        guard let url = makeURL(configuration.ollamaURL, "/api/tags") else { return [] }
        let json = try await httpGetJSON(url, timeout: 3)
        let models = (json as? [String: Any])?["models"] as? [[String: Any]] ?? []
        return models.compactMap { $0["name"] as? String }
    }

    public func checkAvailability() async -> BackendStatus {
        do {
            let models = try await installedModels()
            if models.isEmpty { return .missing("Ollama is running but has no models. Run: ollama pull llama3.2") }
            let chosen = configuration.model(for: id) ?? models[0]
            return .available("\(configuration.ollamaURL) · \(chosen)")
        } catch {
            return .missing("Not running at \(configuration.ollamaURL). \(id.setupHint)")
        }
    }

    public func complete(_ request: AIRequest) async throws -> String {
        guard let url = makeURL(configuration.ollamaURL, "/api/chat") else {
            throw BackendError.failed("Invalid Ollama URL: \(configuration.ollamaURL)")
        }
        do {
            var model = configuration.model(for: id, override: request.model)
            if model == nil { model = try await installedModels().first }
            guard let model else { throw BackendError.unavailable("Ollama has no models installed. Run: ollama pull llama3.2") }

            let json = try await httpPostJSON(url, body: [
                "model": model,
                "messages": messages(request),
                "stream": false,
                "options": ["temperature": 0.2],
            ], timeout: configuration.timeout)
            let content = ((json as? [String: Any])?["message"] as? [String: Any])?["content"] as? String
            guard let content else { throw BackendError.emptyResponse }
            return content
        } catch {
            throw mapURLError(error, id: id, base: configuration.ollamaURL)
        }
    }
}

// MARK: - OpenAI-compatible local server (LM Studio, Jan, llama.cpp, LocalAI, vLLM …)

public struct OpenAICompatibleBackend: AIBackend {
    public let id = BackendID.openAICompatible
    let configuration: BackendConfiguration

    public init(configuration: BackendConfiguration) { self.configuration = configuration }

    public func availableModels() async throws -> [String] {
        guard let url = makeURL(configuration.openAIBaseURL, "/models") else { return [] }
        let json = try await httpGetJSON(url, timeout: 3)
        let data = (json as? [String: Any])?["data"] as? [[String: Any]] ?? []
        return data.compactMap { $0["id"] as? String }
    }

    public func checkAvailability() async -> BackendStatus {
        do {
            let models = try await availableModels()
            let chosen = configuration.model(for: id) ?? models.first ?? "server default"
            return .available("\(configuration.openAIBaseURL) · \(chosen)")
        } catch {
            return .missing("No server at \(configuration.openAIBaseURL). \(id.setupHint)")
        }
    }

    public func complete(_ request: AIRequest) async throws -> String {
        guard let url = makeURL(configuration.openAIBaseURL, "/chat/completions") else {
            throw BackendError.failed("Invalid server URL: \(configuration.openAIBaseURL)")
        }
        do {
            var body: [String: Any] = ["messages": messages(request), "temperature": 0.2, "stream": false]
            if let model = configuration.model(for: id, override: request.model) {
                body["model"] = model
            } else if let first = try? await availableModels().first {
                body["model"] = first
            }
            let json = try await httpPostJSON(url, body: body, timeout: configuration.timeout)
            let choices = (json as? [String: Any])?["choices"] as? [[String: Any]]
            let content = (choices?.first?["message"] as? [String: Any])?["content"] as? String
            guard let content else { throw BackendError.emptyResponse }
            return content
        } catch {
            throw mapURLError(error, id: id, base: configuration.openAIBaseURL)
        }
    }
}
