// Grammable — free, open-source AI writing assistant for macOS.
// Copyright (C) 2026 Udaya Lakmal
//
// This program is free software: you can redistribute it and/or modify it under the
// terms of the GNU General Public License as published by the Free Software Foundation,
// either version 3 of the License, or (at your option) any later version.
// This program is distributed WITHOUT ANY WARRANTY. See the LICENSE file for details.

import AppKit

if CommandLine.arguments.count > 1, CommandLine.arguments[1].hasPrefix("--") {
    // Command-line mode, e.g.  Grammable --run fix-grammar --backend ollama "teh text"
    exit(CommandLineTool.run(Array(CommandLine.arguments.dropFirst())))
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
app.run()
