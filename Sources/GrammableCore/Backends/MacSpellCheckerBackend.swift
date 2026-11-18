// Grammable — Copyright (C) 2026 Udaya Lakmal — GPL-3.0-or-later

import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// The spelling and grammar checker built into macOS (the one behind Edit › Spelling and Grammar).
/// No AI and no setup: always available, fully offline. It fixes spelling and grammar but cannot
/// rewrite, so the engine only uses it for fix-mode presets.
public struct MacSpellCheckerBackend: AIBackend {
    public let id = BackendID.builtIn

    public init() {}

    public func checkAvailability() async -> BackendStatus {
        .available("Built into macOS · spelling and grammar fixes only")
    }

    public func complete(_ request: AIRequest) async throws -> String {
        #if canImport(AppKit)
        let text = request.text
        return await MainActor.run { Self.correct(text) }
        #else
        throw BackendError.unavailable("The macOS spell checker is not available.")
        #endif
    }

    #if canImport(AppKit)
    /// Applies the checker's first suggestion for every spelling and grammar issue it finds.
    @MainActor
    public static func correct(_ text: String) -> String {
        let checker = NSSpellChecker.shared
        let tag = NSSpellChecker.uniqueSpellDocumentTag()
        defer { checker.closeSpellDocument(withTag: tag) }

        let ns = text as NSString
        let types = NSTextCheckingResult.CheckingType.spelling.rawValue
            | NSTextCheckingResult.CheckingType.grammar.rawValue
        let results = checker.check(
            text, range: NSRange(location: 0, length: ns.length), types: types, options: nil,
            inSpellDocumentWithTag: tag, orthography: nil, wordCount: nil)

        var replacements: [(range: NSRange, text: String)] = []
        for result in results {
            if result.resultType == .spelling {
                let guess = checker.correction(forWordRange: result.range, in: text,
                                               language: checker.language(), inSpellDocumentWithTag: tag)
                    ?? checker.guesses(forWordRange: result.range, in: text,
                                       language: nil, inSpellDocumentWithTag: tag)?.first
                if let guess { replacements.append((result.range, guess)) }
            } else if result.resultType == .grammar {
                for detail in result.grammarDetails ?? [] {
                    guard let corrections = detail[NSGrammarCorrections] as? [String],
                          let first = corrections.first,
                          let local = (detail[NSGrammarRange] as? NSValue)?.rangeValue else { continue }
                    // Grammar detail ranges are relative to the start of the flagged sentence.
                    let range = NSRange(location: result.range.location + local.location, length: local.length)
                    guard NSMaxRange(range) <= ns.length else { continue }
                    replacements.append((range, first))
                }
            }
        }

        // Apply from the end so earlier ranges stay valid; skip overlapping suggestions.
        let output = NSMutableString(string: text)
        var lowerBound = Int.max
        for item in replacements.sorted(by: { $0.range.location > $1.range.location }) {
            guard NSMaxRange(item.range) <= lowerBound else { continue }
            output.replaceCharacters(in: item.range, with: item.text)
            lowerBound = item.range.location
        }
        return output as String
    }
    #endif
}
