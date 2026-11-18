// Grammable — Copyright (C) 2026 Udaya Lakmal — GPL-3.0-or-later

import AppKit
import SwiftUI
import GrammableCore

/// Desktop apps that come from the same companies as the agent CLIs. Having the app installed
/// doesn't give Grammable a command-line tool, which is a common source of confusion.
enum DesktopApps {
    static let paths: [BackendID: [String]] = [
        .claude: ["/Applications/Claude.app"],
        .codex: ["/Applications/Codex.app", "/Applications/ChatGPT.app"],
        .antigravity: ["/Applications/Antigravity.app", "/Applications/Antigravity IDE.app"],
        .devin: ["/Applications/Devin.app"],
    ]

    /// The installed desktop app's name for a backend, if any.
    static func installedApp(for id: BackendID) -> String? {
        for path in paths[id] ?? [] where FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        }
        return nil
    }

    static var cliBackends: [BackendID] { BackendID.allCases.filter { $0.executableName != nil } }
}

/// Shown in Settings › AI Backends when none of the agent command-line tools is ready.
struct CLISetupNote: View {
    let statuses: [BackendID: BackendStatus]

    private var appsWithoutCLI: [String] {
        DesktopApps.cliBackends.compactMap { id in
            statuses[id]?.isAvailable == true ? nil : DesktopApps.installedApp(for: id)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "terminal").foregroundStyle(Brand.gradient).font(.title3)
                Text("Use an AI subscription you already have").font(.headline)
            }
            Text("Grammable talks to Claude Code, Codex, Gemini, Antigravity and Devin through their **command-line tools**. Installing only the desktop app isn't enough: install the command-line tool, run it once in Terminal to sign in, then click Refresh.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !appsWithoutCLI.isEmpty {
                Text("Installed without the command-line tool: \(appsWithoutCLI.joined(separator: ", ")).")
                    .font(.callout)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(DesktopApps.cliBackends) { id in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(id.shortName).font(.caption.bold()).frame(width: 78, alignment: .leading)
                        Text(Self.installCommand(id))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
        }
        .padding(.vertical, 4)
    }

    static func installCommand(_ id: BackendID) -> String {
        switch id {
        case .claude: return "npm install -g @anthropic-ai/claude-code && claude"
        case .codex: return "npm install -g @openai/codex && codex"
        case .gemini: return "npm install -g @google/gemini-cli && gemini"
        case .antigravity: return "curl -fsSL https://antigravity.google/cli/install.sh | bash && agy"
        case .devin: return "curl -fsSL https://cli.devin.ai/install.sh | bash && devin auth login"
        default: return ""
        }
    }
}
