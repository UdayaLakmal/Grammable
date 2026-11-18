# Changelog

## Unreleased

- Settings › Privacy now excludes only Terminal and Keychain Access by default; add any other app yourself

## 0.1.5 — 2026-11-18

- New backends: **Antigravity CLI** (`agy`) and **Devin CLI** (`devin`), on your own accounts
- Settings › AI Backends explains that each service's command-line tool is needed (not only its desktop app), lists the install commands when none is set up, and flags apps installed without their CLI
- Devin shows "not signed in" in Settings instead of failing on first use
- Antigravity answers are read from its streamed output as soon as they're ready, so a turn that `agy` keeps open no longer runs into the time limit
- Terminal control codes that some CLIs print are removed from answers

## 0.1.4 — 2026-11-18

- New built-in backend, **macOS Spelling & Grammar**: Fix Grammar & Spelling works with no AI installed, fully offline
- When the chosen AI isn't installed or running, grammar fixes fall back to the macOS checker instead of failing
- **Free offline AI** setup in Settings › AI Backends: download Ollama, start it, and download a small model with a progress bar, then use it as the default
- The action menu explains when no AI is set up, with a Set Up Free AI button
- Removed the Cloud/On-device badge from the action menu header; the footer already names the AI
- Command line: `--run` no longer hangs with backends that need the main thread

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
