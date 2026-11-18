// Grammable — Copyright (C) 2026 Udaya Lakmal — GPL-3.0-or-later

import SwiftUI

// SwiftUI features that arrived in macOS 13, with simple stand-ins on macOS 12 Monterey.

extension View {
    /// Grouped settings form on macOS 13+, a padded plain form on macOS 12.
    @ViewBuilder func groupedFormStyle() -> some View {
        if #available(macOS 13.0, *) {
            formStyle(.grouped)
        } else {
            padding(20)
        }
    }

    /// Lets a custom background show through a TextEditor (macOS 13+).
    @ViewBuilder func hiddenScrollBackground() -> some View {
        if #available(macOS 13.0, *) {
            scrollContentBackground(.hidden)
        } else {
            self
        }
    }

    /// Number keys 1–9 for the first nine menu actions.
    @ViewBuilder func numberShortcut(_ index: Int) -> some View {
        if index < 9 {
            keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
        } else {
            self
        }
    }
}

/// A label on the left and a value on the right, like `LabeledContent` (macOS 13+).
struct SettingRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 12)
            content
        }
    }
}
