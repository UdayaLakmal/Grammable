// Grammable — Copyright (C) 2026 Udaya Lakmal — GPL-3.0-or-later

import Foundation
import ServiceManagement

/// Starts Grammable when you log in, using the macOS login items service.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Turned on by default the first time Grammable runs. The user can switch it off in
    /// Settings or in System Settings › General › Login Items.
    static func enable() {
        do {
            try SMAppService.mainApp.register()
            DiagnosticLog.log("launch at login enabled")
        } catch {
            DiagnosticLog.log("launch at login failed: \(error.localizedDescription)")
        }
    }

    /// If launch at login is on, register again so it points at this copy of the app
    /// (for example after moving from a download folder to /Applications or updating with Homebrew).
    static func refreshLocation() {
        guard isEnabled else { return }
        try? SMAppService.mainApp.register()
    }
}
