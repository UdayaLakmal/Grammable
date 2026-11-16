# Contributing to Grammable

Thanks for helping make a free writing assistant for everyone! 🎉

## Ways to help

- **Share a preset** — the easiest contribution. Add a Markdown file to [`presets/`](presets) (see its README).
- **Report bugs** — include `Grammable --status` output, macOS version and the app you were typing in.
- **Add or improve a backend** — new local servers, better CLI flags, faster defaults.
- **Improve compatibility** — apps where selection or replacement does not work well.

## Development

```bash
git clone https://github.com/UdayaLakmal/Grammable.git
cd Grammable
swift build && swift test         # core library + tests
./scripts/build-app.sh            # dist/Grammable.app
open dist/Grammable.app
```

You can also open `Package.swift` in Xcode.

### Project layout

| Path | What's inside |
|---|---|
| `Sources/GrammableCore/Backends` | AI backends (Claude Code, Codex, Gemini, Ollama, OpenAI-compatible, Apple) and the CLI runner |
| `Sources/GrammableCore/Presets` | Preset model, Markdown parser, store, built-in presets |
| `Sources/GrammableCore/Review` | Prompt builder, output cleanup, word-level diff |
| `Sources/Grammable/Selection` | Accessibility, selection monitor, global hotkey |
| `Sources/Grammable/UI` | Floating pop-up, review card, settings, branding |
| `Sources/Grammable/App` | App delegate, menu bar, command-line mode |
| `scripts/` | App bundling, icon generation |
| `presets/` | Community presets |

### Testing a backend quickly

```bash
.build/debug/Grammable --status
.build/debug/Grammable --run fix-grammar --backend ollama --diff "she dont like it"
```

> **Tip:** each ad-hoc signed rebuild looks like a new app to macOS, so you may need to remove and re-add Grammable under *System Settings → Privacy & Security → Accessibility*.

## Guidelines

- Keep it **free and local-first**: no telemetry, no accounts, no servers of our own.
- **Never log or store user text.**
- Keep `GrammableCore` free of AppKit so it stays testable.
- Add tests for logic changes (`Tests/GrammableTests`).
- New source files start with the GPL-3.0 header used in the existing files.

By contributing you agree that your contributions are licensed under GPL-3.0-or-later.
