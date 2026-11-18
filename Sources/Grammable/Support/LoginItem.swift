// Grammable — Copyright (C) 2026 Udaya Lakmal — GPL-3.0-or-later

import Foundation
import ServiceManagement

/// Starts Grammable when you log in.
///
/// macOS 13 and later use the system login items service (shown in System Settings › General ›
/// Login Items). macOS 12 has no such API for a single app, so a small launch agent in
/// `~/Library/LaunchAgents` opens Grammable at login instead.
enum LoginItem {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) { return SMAppService.mainApp.status == .enabled }
        return FileManager.default.fileExists(atPath: LaunchAgent.url.path)
    }

    static func setEnabled(_ enabled: Bool) throws {
        if #available(macOS 13.0, *) {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } else {
            if enabled { try LaunchAgent.write() } else { try LaunchAgent.remove() }
        }
    }

    /// Turned on by default the first time Grammable runs. The user can switch it off in Settings.
    static func enable() {
        do {
            try setEnabled(true)
            DiagnosticLog.log("launch at login enabled")
        } catch {
            DiagnosticLog.log("launch at login failed: \(error.localizedDescription)")
        }
    }

    /// If launch at login is on, register again so it points at this copy of the app
    /// (for example after moving from a download folder to /Applications or updating with Homebrew).
    static func refreshLocation() {
        guard isEnabled else { return }
        try? setEnabled(true)
    }

    /// macOS 12 fallback: a per-user launch agent that runs `open <Grammable.app>` at login.
    private enum LaunchAgent {
        static let label = "io.github.udayalakmal.grammable.login"

        static var url: URL {
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/LaunchAgents/\(label).plist")
        }

        static func write() throws {
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": ["/usr/bin/open", Bundle.main.bundlePath],
                "RunAtLoad": true,
                "LimitLoadToSessionType": "Aqua",
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }

        static func remove() throws {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }
}
