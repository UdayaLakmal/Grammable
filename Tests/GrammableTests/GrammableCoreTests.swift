// Grammable — Copyright (C) 2026 Udaya Lakmal — GPL-3.0-or-later

import XCTest
@testable import GrammableCore

final class TextDiffTests: XCTestCase {

    func testIdenticalTextHasNoChanges() {
        let diff = TextDiff(original: "Hello world.", revised: "Hello world.")
        XCTAssertTrue(diff.changes.isEmpty)
        XCTAssertEqual(diff.apply(accepted: []), "Hello world.")
    }

    func testWordReplacements() {
        let original = "she go to school yesterday"
        let revised = "She went to school yesterday."
        let diff = TextDiff(original: original, revised: revised)
        XCTAssertEqual(diff.changes.count, 3)
        XCTAssertEqual(diff.changes[0].original, "she")
        XCTAssertEqual(diff.changes[0].replacement, "She")
        XCTAssertEqual(diff.changes[1].original, "go")
        XCTAssertEqual(diff.changes[1].replacement, "went")
        XCTAssertTrue(diff.changes[2].isInsertion)

        let all = Set(diff.changes.map(\.id))
        XCTAssertEqual(diff.apply(accepted: all), revised)
        XCTAssertEqual(diff.apply(accepted: []), original)
    }

    func testPartialAcceptance() {
        let diff = TextDiff(original: "teh cat sat on teh mat", revised: "the cat sat on the mat")
        XCTAssertEqual(diff.changes.count, 2)
        XCTAssertEqual(diff.apply(accepted: [diff.changes[0].id]), "the cat sat on teh mat")
        XCTAssertEqual(diff.apply(accepted: [diff.changes[1].id]), "teh cat sat on the mat")
    }

    func testTokenizerKeepsApostrophesAndPunctuation() {
        XCTAssertEqual(TextDiff.tokenize("Don't stop, ok?"), ["Don't", " ", "stop", ",", " ", "ok", "?"])
    }

    func testMultilineAndUnicode() {
        let original = "Line one\nLine too 😀\n"
        let revised = "Line one\nLine two 😀\n"
        let diff = TextDiff(original: original, revised: revised)
        XCTAssertEqual(diff.changes.count, 1)
        XCTAssertEqual(diff.apply(accepted: Set(diff.changes.map(\.id))), revised)
    }
}

final class PresetParserTests: XCTestCase {

    func testParsesFrontMatter() throws {
        let text = """
        ---
        name: "Pirate Speak"
        icon: flag
        mode: fix
        backend: Ollama   # local only
        model: llama3.2
        order: 5
        ---
        Rewrite like a pirate.
        """
        let preset = try PresetParser.parse(text, id: "pirate")
        XCTAssertEqual(preset.name, "Pirate Speak")
        XCTAssertEqual(preset.icon, "flag")
        XCTAssertEqual(preset.mode, .fix)
        XCTAssertEqual(preset.backendID, .ollama)
        XCTAssertEqual(preset.model, "llama3.2")
        XCTAssertEqual(preset.order, 5)
        XCTAssertEqual(preset.instructions, "Rewrite like a pirate.")
    }

    func testNoFrontMatterUsesDefaults() throws {
        let preset = try PresetParser.parse("Translate to French.", id: "to-french")
        XCTAssertEqual(preset.name, "To French")
        XCTAssertEqual(preset.mode, .rewrite)
        XCTAssertNil(preset.backend)
        XCTAssertEqual(preset.instructions, "Translate to French.")
    }

    func testEmptyBodyThrows() {
        XCTAssertThrowsError(try PresetParser.parse("---\nname: x\n---\n   \n", id: "x"))
    }

    func testRoundTrip() throws {
        let original = BuiltInPresets.all[0]
        let parsed = try PresetParser.parse(PresetParser.serialize(original), id: original.id)
        XCTAssertEqual(parsed.name, original.name)
        XCTAssertEqual(parsed.mode, original.mode)
        XCTAssertEqual(parsed.order, original.order)
        XCTAssertEqual(parsed.instructions, original.instructions)
    }

    func testStoreOverridesBuiltInsAndAddsCustom() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try "---\nname: My Fixer\nmode: fix\n---\nFix it.".write(
            to: dir.appendingPathComponent("fix-grammar.md"), atomically: true, encoding: .utf8)
        try "Say it like Shakespeare.".write(
            to: dir.appendingPathComponent("shakespeare.md"), atomically: true, encoding: .utf8)
        try "---\nname: Broken\n---\n".write(
            to: dir.appendingPathComponent("broken.md"), atomically: true, encoding: .utf8)

        let result = PresetStore(directory: dir).load()
        XCTAssertEqual(result.errors.count, 1)
        let fixer = try XCTUnwrap(result.presets.first { $0.id == "fix-grammar" })
        XCTAssertEqual(fixer.name, "My Fixer")
        XCTAssertFalse(fixer.isBuiltIn)
        XCTAssertEqual(fixer.order, 10, "overrides keep the built-in menu position")
        XCTAssertTrue(result.presets.contains { $0.id == "shakespeare" })
        XCTAssertEqual(result.presets.count, BuiltInPresets.all.count + 1)
    }
}

final class PromptBuilderTests: XCTestCase {

    func testStripsCodeFenceAndPreamble() {
        let raw = "Here is the corrected text:\n```\nHello there.\n```"
        XCTAssertEqual(PromptBuilder.clean(raw, original: "hello there"), "Hello there.")
        XCTAssertEqual(PromptBuilder.clean("```text\nHi.\n```", original: "hi"), "Hi.")
    }

    func testStripsAddedQuotesButKeepsOriginalOnes() {
        XCTAssertEqual(PromptBuilder.clean("\"Hello.\"", original: "hello"), "Hello.")
        XCTAssertEqual(PromptBuilder.clean("\"Hello.\"", original: "\"hello\""), "\"Hello.\"")
    }

    func testRestoresSurroundingWhitespace() {
        XCTAssertEqual(PromptBuilder.clean("Fixed.\n", original: "  fixd. \n"), "  Fixed. \n")
    }

    func testExtractsTextTagsFromChattyOutput() {
        let raw = "I'd be happy to help. Here's a rewritten version:\n\n<text>\nCould you send the report?\n</text>\nLet me know!"
        XCTAssertEqual(PromptBuilder.clean(raw, original: "send report"), "Could you send the report?")
        XCTAssertEqual(PromptBuilder.clean("Sure:\n<text>\nOk then.", original: "ok"), "Ok then.")
    }

    func testStripsEchoedTextTags() {
        XCTAssertEqual(PromptBuilder.clean("<text>\nDone.\n</text>", original: "done"), "Done.")
    }
}

final class BackendTests: XCTestCase {

    func testPresetBackendOverride() {
        var preset = BuiltInPresets.all[0]
        XCTAssertEqual(GrammableEngine.resolveBackend(for: preset, default: .claude), .claude)
        preset.backend = "ollama"
        XCTAssertEqual(GrammableEngine.resolveBackend(for: preset, default: .claude), .ollama)
        preset.backend = "nonsense"
        XCTAssertEqual(GrammableEngine.resolveBackend(for: preset, default: .codex), .codex)
    }

    func testPrivacyClassification() {
        XCTAssertTrue(BackendID.ollama.isOnDevice)
        XCTAssertTrue(BackendID.apple.isOnDevice)
        XCTAssertFalse(BackendID.claude.isOnDevice)
    }

    func testMissingCustomExecutableIsUnavailable() async {
        let config = BackendConfiguration(executablePaths: [.codex: "/nonexistent/codex"])
        let status = await BackendFactory.make(.codex, configuration: config).checkAvailability()
        XCTAssertFalse(status.isAvailable)
    }
}

final class CommunityPresetTests: XCTestCase {
    /// Every file in the repository's presets/ folder must parse.
    func testRepositoryPresetsParse() throws {
        let presetsDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("presets")
        let files = try FileManager.default.contentsOfDirectory(at: presetsDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" && $0.lastPathComponent != "README.md" }
        XCTAssertFalse(files.isEmpty)
        for url in files {
            let preset = try PresetParser.parse(String(contentsOf: url, encoding: .utf8),
                                                id: url.deletingPathExtension().lastPathComponent, fileURL: url)
            XCTAssertFalse(preset.name.isEmpty, url.lastPathComponent)
            if let backend = preset.backend {
                XCTAssertNotNil(BackendID(rawValue: backend), "\(url.lastPathComponent): unknown backend \(backend)")
            }
        }
    }
}
