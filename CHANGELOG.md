# Changelog

## 0.1.3 — 2026-11-18

- Monterey: Settings tabs now scroll and start at the top, so the tab bar stays visible
- Monterey: the G button and menu respond to the first click
- The action menu says when your default AI isn't installed or running, with a Set Up AI button

## 0.1.2 — 2026-11-18

- Runs on macOS 12 Monterey (previously macOS 13 Ventura or later)
- On Monterey, launch at login uses a small launch agent in `~/Library/LaunchAgents`, removed when you turn the option off

## 0.1.1 — 2026-11-17

- Grammable now starts at login by default, quietly in the menu bar
- Settings opens automatically only on the first launch, no longer after every restart (open Grammable again to reach it)
- Launch at login follows the app when it moves (for example from Downloads to /Applications or after a Homebrew upgrade)

## 0.1.0 — 2026-11-16

First public release.

- Menu bar app with enable/disable switch
- Floating **G** button when text is selected in any app, plus global shortcut `⌃⌥G`
- Backends: Claude Code, Codex CLI, Gemini CLI, Ollama, LM Studio / OpenAI-compatible servers, Apple Intelligence (macOS 26+, Xcode 26 builds)
- Default backend with per-preset override
- Review card: accept/reject individual grammar fixes; editable before/after for rewrites
- 9 built-in presets and Markdown custom presets in `~/.grammable/presets`
- On-device / Cloud privacy badge, password-field protection, per-app exclusions, clipboard restore
- Command-line mode (`--status`, `--list`, `--run`)
