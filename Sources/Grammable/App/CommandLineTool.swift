// Grammable — Copyright (C) 2026 Udaya Lakmal — GPL-3.0-or-later

import AppKit
import GrammableCore

/// Scriptable interface — handy for testing presets and for shell / Shortcuts workflows.
///
///     Grammable --list
///     Grammable --status
///     Grammable --run <preset-id> [--backend <id>] [--diff] [text]    (text from stdin if omitted)
enum CommandLineTool {

    static let usage = """
    Grammable — free AI grammar checker & rewriter for macOS

    Usage:
      Grammable --list                                    List presets
      Grammable --status                                  Show which AI backends are available
      Grammable --run <preset> [--backend <id>] [--diff] [text]
                                                          Run a preset (reads stdin when no text is given)
      Grammable --help

    Backends: \(BackendID.allCases.map(\.rawValue).joined(separator: ", "))
    """

    static func run(_ args: [String]) -> Int32 {
        switch args.first {
        case "--list":
            for preset in PresetStore().load().presets {
                print("\(preset.id.padding(toLength: 18, withPad: " ", startingAt: 0)) \(preset.mode.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)) \(preset.name)")
            }
            return 0
        case "--status":
            return waitFor {
                let config = AppSettings.shared.backendConfiguration
                for id in BackendID.allCases {
                    let status = await BackendFactory.make(id, configuration: config).checkAvailability()
                    print("\(status.isAvailable ? "✓" : "✗") \(id.rawValue.padding(toLength: 18, withPad: " ", startingAt: 0)) \(status.detail)")
                }
                return 0
            }
        case "--run":
            return runPreset(Array(args.dropFirst()))
        case "--render-ui":
            let dir = URL(fileURLWithPath: args.dropFirst().first ?? "ui-snapshots")
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.prohibited)
            return MainActor.assumeIsolated { UISnapshot.renderAll(to: dir) }
        default:
            print(usage)
            return args.first == "--help" ? 0 : 64
        }
    }

    private static func runPreset(_ args: [String]) -> Int32 {
        var rest = args
        guard !rest.isEmpty else { print(usage); return 64 }
        let presetID = rest.removeFirst().lowercased()
        var backend = AppSettings.shared.defaultBackend
        var showDiff = false
        var words: [String] = []
        while !rest.isEmpty {
            let arg = rest.removeFirst()
            switch arg {
            case "--backend":
                guard let raw = rest.first, let id = BackendID(rawValue: raw.lowercased()) else {
                    fputs("Unknown backend. Use one of: \(BackendID.allCases.map(\.rawValue).joined(separator: ", "))\n", stderr)
                    return 64
                }
                rest.removeFirst()
                backend = id
            case "--diff":
                showDiff = true
            default:
                words.append(arg)
            }
        }

        var text = words.joined(separator: " ")
        if text.isEmpty {
            text = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fputs("No text given.\n", stderr); return 64
        }
        guard var preset = PresetStore().load().presets.first(where: { $0.id == presetID }) else {
            fputs("No preset named “\(presetID)”. Run: Grammable --list\n", stderr); return 64
        }
        if args.contains("--backend") { preset.backend = backend.rawValue }

        let finalPreset = preset, finalText = text, finalBackend = backend, finalShowDiff = showDiff
        return waitFor {
            let preset = finalPreset, text = finalText, backend = finalBackend, showDiff = finalShowDiff
            do {
                let result = try await GrammableEngine.run(
                    preset: preset, text: text, defaultBackend: backend,
                    configuration: AppSettings.shared.backendConfiguration)
                if showDiff {
                    for change in result.diff.changes {
                        fputs("  “\(change.original)” → “\(change.replacement)”\n", stderr)
                    }
                    fputs("[\(result.backend.displayName), \(String(format: "%.1f", result.duration))s, \(result.diff.changes.count) changes]\n", stderr)
                }
                print(result.suggestion)
                return 0
            } catch {
                fputs("Error: \(error.localizedDescription)\n", stderr)
                return 1
            }
        }
    }

    /// Runs async work from synchronous top-level code.
    private static func waitFor(_ work: @escaping @Sendable () async -> Int32) -> Int32 {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox()
        Task.detached {
            box.value = await work()
            semaphore.signal()
        }
        semaphore.wait()
        return box.value
    }

    private final class ResultBox: @unchecked Sendable { var value: Int32 = 0 }
}
