// Grammable — Copyright (C) 2026 Udaya Lakmal — GPL-3.0-or-later

import XCTest
@testable import GrammableCore

/// Serves canned Ollama responses for requests to http://ollama.test.
final class FakeOllamaProtocol: URLProtocol {
    nonisolated(unsafe) static var body = ""

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "ollama.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class OfflineTests: XCTestCase {
    override func setUp() { URLProtocol.registerClass(FakeOllamaProtocol.self) }
    override func tearDown() { URLProtocol.unregisterClass(FakeOllamaProtocol.self) }

    func testPullReportsProgressAcrossLayersAndFinishes() async throws {
        FakeOllamaProtocol.body = """
        {"status":"pulling manifest"}
        {"status":"pulling a","digest":"a","total":300,"completed":150}
        {"status":"pulling b","digest":"b","total":100,"completed":100}
        {"status":"pulling a","digest":"a","total":300,"completed":300}
        {"status":"success"}

        """
        let log = Log()
        try await OllamaSetup.pull(model: "llama3.2:1b", baseURL: "http://ollama.test") { fraction, _ in
            log.add(fraction)
        }
        XCTAssertEqual(log.values.first, 0)
        XCTAssertTrue(log.values.contains(0.625)) // (150 + 100) / 400
        XCTAssertEqual(log.values.last, 1)
    }

    func testPullSurfacesOllamaErrors() async {
        FakeOllamaProtocol.body = "{\"error\":\"pull model manifest: file does not exist\"}\n"
        do {
            try await OllamaSetup.pull(model: "nope", baseURL: "http://ollama.test") { _, _ in }
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("file does not exist"))
        }
    }

    func testRewriteWithBuiltInCheckerExplainsThatAnAIIsNeeded() async {
        let preset = BuiltInPresets.all.first { $0.mode != .fix }!
        do {
            _ = try await GrammableEngine.run(preset: preset, text: "hello", defaultBackend: .builtIn,
                                              configuration: BackendConfiguration())
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BackendError, .unavailable(GrammableEngine.needsAIMessage))
        }
    }

    func testTerminalCodesAreStrippedFromCLIOutput() {
        XCTAssertEqual(CLIRunner.stripTerminalCodes("\u{1B}[?2004lThis sentence has\u{1B}[0m two mistakes."),
                       "This sentence has two mistakes.")
        XCTAssertEqual(CLIRunner.stripTerminalCodes("\u{1B}]0;title\u{07}Hello"), "Hello")
    }

    func testAntigravityAndDevinAreCloudCLIBackends() {
        XCTAssertEqual(BackendID.antigravity.executableName, "agy")
        XCTAssertEqual(BackendID.devin.executableName, "devin")
        XCTAssertFalse(BackendID.antigravity.isOnDevice)
        XCTAssertFalse(BackendID.devin.isOnDevice)
        XCTAssertEqual(BackendID(rawValue: "antigravity"), .antigravity)
        XCTAssertEqual(BackendID(rawValue: "devin"), .devin)
    }

    func testMissingCLIBackendStillFixesGrammarWithBuiltInChecker() async throws {
        let preset = BuiltInPresets.all.first { $0.mode == .fix }!
        var config = BackendConfiguration()
        config.executablePaths[.antigravity] = "/nonexistent/agy"
        let result = try await GrammableEngine.run(preset: preset, text: "teh cat", defaultBackend: .antigravity,
                                                   configuration: config)
        XCTAssertEqual(result.backend, .builtIn)
    }

    func testAntigravityStreamReturnsAnswerWhenResponseStepIsDone() {
        let parser = AntigravityStreamParser()
        func step(_ state: String, _ type: String, _ delta: String = "") -> String {
            "{\"event\":\"step_update\",\"step_update\":{\"state\":\"\(state)\",\"step_type\":\"\(type)\",\"text_delta\":\"\(delta)\"}}"
        }
        if case .keepReading = parser.handle("{\"event\":\"init\"}") {} else { XCTFail() }
        if case .keepReading = parser.handle(step("DONE", "user_input")) {} else { XCTFail() }
        // A response step that ends with no text (thinking only) is skipped.
        if case .keepReading = parser.handle(step("DONE", "agent_response")) {} else { XCTFail() }
        if case .keepReading = parser.handle(step("ACTIVE", "agent_response", "This sentence")) {} else { XCTFail() }
        guard case .finished(let answer) = parser.handle(step("DONE", "agent_response", " has two mistakes.")) else {
            return XCTFail("expected the answer")
        }
        XCTAssertEqual(answer, "This sentence has two mistakes.")
    }

    func testAntigravityStreamReportsErrorSteps() {
        let parser = AntigravityStreamParser()
        let line = "{\"event\":\"step_update\",\"step_update\":{\"state\":\"DONE\",\"step_type\":\"error_message\"}}"
        guard case .failed = parser.handle(line) else { return XCTFail("expected an error") }
    }

    func testBuiltInCheckerIsAlwaysAvailableAndOnDevice() async {
        XCTAssertTrue(BackendID.builtIn.isOnDevice)
        XCTAssertFalse(BackendID.builtIn.canRewrite)
        let status = await MacSpellCheckerBackend().checkAvailability()
        XCTAssertTrue(status.isAvailable)
    }
}

private final class Log: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Double] = []
    var values: [Double] { lock.lock(); defer { lock.unlock() }; return storage }
    func add(_ value: Double) { lock.lock(); storage.append(value); lock.unlock() }
}
