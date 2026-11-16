// Grammable — Copyright (C) 2026 Udaya Lakmal — GPL-3.0-or-later

import Foundation

/// Presets that ship with the app. A user preset file with the same id
/// (e.g. `fix-grammar.md`) overrides the built-in one.
public enum BuiltInPresets {
    public static let all: [Preset] = [
        Preset(
            id: "fix-grammar",
            name: "Fix Grammar & Spelling",
            icon: "checkmark.seal",
            mode: .fix,
            order: 10,
            instructions: """
            Correct spelling, grammar, punctuation, capitalization and word-usage mistakes.
            Make the minimum number of changes needed. Do not rephrase sentences that are already correct.
            Keep the author's tone, style, wording, language and formatting.
            """,
            isBuiltIn: true
        ),
        Preset(
            id: "improve",
            name: "Improve Writing",
            icon: "sparkles",
            mode: .rewrite,
            order: 20,
            instructions: """
            Improve the writing: make it clearer, smoother and easier to read while keeping the same meaning,
            tone and approximate length. Fix any grammar or spelling mistakes.
            """,
            isBuiltIn: true
        ),
        Preset(
            id: "professional",
            name: "Make Professional",
            icon: "briefcase",
            mode: .rewrite,
            order: 30,
            instructions: """
            Rewrite the text in a clear, polite and professional tone suitable for work communication.
            Keep the same meaning and all facts. Avoid jargon and filler.
            """,
            isBuiltIn: true
        ),
        Preset(
            id: "friendly",
            name: "Make Friendly",
            icon: "face.smiling",
            mode: .rewrite,
            order: 40,
            instructions: """
            Rewrite the text in a warm, friendly and approachable tone. Keep it natural and keep the same meaning.
            Do not add emojis unless the original uses them.
            """,
            isBuiltIn: true
        ),
        Preset(
            id: "confident",
            name: "Make Confident",
            icon: "bolt",
            mode: .rewrite,
            order: 50,
            instructions: """
            Rewrite the text so it sounds confident and assertive. Remove hedging words such as
            "just", "maybe", "I think", "sorry to bother". Keep it polite and keep the same meaning.
            """,
            isBuiltIn: true
        ),
        Preset(
            id: "concise",
            name: "Make Concise",
            icon: "scissors",
            mode: .rewrite,
            order: 60,
            instructions: """
            Make the text shorter and more direct. Remove redundancy and filler while keeping every key point.
            """,
            isBuiltIn: true
        ),
        Preset(
            id: "simplify",
            name: "Simplify",
            icon: "text.badge.minus",
            mode: .rewrite,
            order: 70,
            instructions: """
            Rewrite the text in plain, simple language that is easy for anyone to understand.
            Use short sentences and common words. Keep the same meaning.
            """,
            isBuiltIn: true
        ),
        Preset(
            id: "bullets",
            name: "Format as Bullet Points",
            icon: "list.bullet",
            mode: .rewrite,
            order: 80,
            instructions: """
            Reformat the text as a clean bulleted list using "- " bullets. One idea per bullet.
            Keep the original wording where possible and fix obvious mistakes.
            """,
            isBuiltIn: true
        ),
        Preset(
            id: "email",
            name: "Format as Email",
            icon: "envelope",
            mode: .rewrite,
            order: 90,
            instructions: """
            Turn the text into a well-structured email with a greeting, short clear paragraphs and a closing line.
            Do not invent names, dates or facts; use neutral placeholders like [Name] only when needed.
            """,
            isBuiltIn: true
        ),
    ]
}
