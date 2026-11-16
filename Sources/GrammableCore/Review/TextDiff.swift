// Grammable — Copyright (C) 2026 Udaya Lakmal — GPL-3.0-or-later

import Foundation

/// One edit between the original and the suggested text.
public struct TextChange: Identifiable, Hashable, Sendable {
    public let id: Int
    public let original: String
    public let replacement: String

    public var isInsertion: Bool { original.isEmpty }
    public var isDeletion: Bool { replacement.isEmpty }
}

/// A word-level diff that can be partially applied.
public struct TextDiff: Sendable {
    public enum Segment: Hashable, Sendable {
        case same(String)
        case change(TextChange)
    }

    public let segments: [Segment]

    public var changes: [TextChange] {
        segments.compactMap { if case .change(let c) = $0 { return c } else { return nil } }
    }

    /// Builds the final text, applying only the accepted change ids.
    public func apply(accepted: Set<Int>) -> String {
        var out = ""
        for segment in segments {
            switch segment {
            case .same(let s): out += s
            case .change(let c): out += accepted.contains(c.id) ? c.replacement : c.original
            }
        }
        return out
    }

    public init(original: String, revised: String) {
        let old = Self.tokenize(original)
        let new = Self.tokenize(revised)
        let diff = new.difference(from: old)

        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in diff {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        var segments: [Segment] = []
        var same = ""
        var nextID = 0
        var i = 0, j = 0
        while i < old.count || j < new.count {
            let iRemoved = i < old.count && removed.contains(i)
            let jInserted = j < new.count && inserted.contains(j)
            if !iRemoved && !jInserted && i < old.count && j < new.count {
                same += old[i]
                i += 1; j += 1
                continue
            }
            var from = "", to = ""
            while i < old.count && removed.contains(i) { from += old[i]; i += 1 }
            while j < new.count && inserted.contains(j) { to += new[j]; j += 1 }
            if from.isEmpty && to.isEmpty {
                // Defensive: should not happen with a valid difference; avoid an infinite loop.
                if i < old.count { same += old[i]; i += 1 }
                if j < new.count { j += 1 }
                continue
            }
            if !same.isEmpty { segments.append(.same(same)); same = "" }
            segments.append(.change(TextChange(id: nextID, original: from, replacement: to)))
            nextID += 1
        }
        if !same.isEmpty { segments.append(.same(same)) }
        self.segments = segments
    }

    /// Splits text into words (letters, digits, apostrophes), whitespace runs and single symbols.
    static func tokenize(_ text: String) -> [String] {
        enum Kind { case word, space, other }
        func kind(_ c: Character) -> Kind {
            if c.isLetter || c.isNumber || c == "'" || c == "’" { return .word }
            if c.isWhitespace { return .space }
            return .other
        }
        var tokens: [String] = []
        var current = ""
        var currentKind: Kind?
        for c in text {
            let k = kind(c)
            if k == .other {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(c))
                currentKind = nil
            } else if k == currentKind {
                current.append(c)
            } else {
                if !current.isEmpty { tokens.append(current) }
                current = String(c)
                currentKind = k
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}
