// Grammable — Copyright (C) 2026 Udaya Lakmal — GPL-3.0-or-later

import AppKit
import SwiftUI
import GrammableCore

enum Brand {
    static let indigo = Color(red: 0.31, green: 0.27, blue: 0.90)
    static let violet = Color(red: 0.58, green: 0.20, blue: 0.92)
    static let pink = Color(red: 0.93, green: 0.28, blue: 0.60)

    static let gradient = LinearGradient(
        colors: [indigo, violet, pink], startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let repositoryURL = URL(string: "https://github.com/UdayaLakmal/Grammable")!
    static let releasesURL = URL(string: "https://github.com/UdayaLakmal/Grammable/releases")!
    static let issuesURL = URL(string: "https://github.com/UdayaLakmal/Grammable/issues")!
    static let sponsorURL = URL(string: "https://ko-fi.com/udayalakmal")!
    static let presetsURL = URL(string: "https://github.com/UdayaLakmal/Grammable/tree/main/presets")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// Menu bar icon: a rounded "G" with a spark, drawn as a template image so it
    /// follows light/dark menu bars automatically.
    static func menuBarImage(enabled: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let font = NSFont.systemFont(ofSize: 15, weight: .heavy)
            let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 15) } ?? font
            let attrs: [NSAttributedString.Key: Any] = [.font: rounded, .foregroundColor: NSColor.black]
            let g = NSAttributedString(string: "G", attributes: attrs)
            let gSize = g.size()
            g.draw(at: NSPoint(x: 0.5, y: (size.height - gSize.height) / 2 - 0.5))

            // Four-point spark in the top-right corner.
            let c = NSPoint(x: 14.5, y: 14.2), r: CGFloat = 3.6, w: CGFloat = 1.0
            let spark = NSBezierPath()
            spark.move(to: NSPoint(x: c.x, y: c.y + r))
            spark.line(to: NSPoint(x: c.x + w, y: c.y + w))
            spark.line(to: NSPoint(x: c.x + r, y: c.y))
            spark.line(to: NSPoint(x: c.x + w, y: c.y - w))
            spark.line(to: NSPoint(x: c.x, y: c.y - r))
            spark.line(to: NSPoint(x: c.x - w, y: c.y - w))
            spark.line(to: NSPoint(x: c.x - r, y: c.y))
            spark.line(to: NSPoint(x: c.x - w, y: c.y + w))
            spark.close()
            NSColor.black.setFill()
            spark.fill()

            if !enabled {
                let slash = NSBezierPath()
                slash.move(to: NSPoint(x: 1, y: 1))
                slash.line(to: NSPoint(x: 17, y: 17))
                slash.lineWidth = 1.8
                slash.lineCapStyle = .round
                NSColor.black.setStroke()
                slash.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = enabled ? "Grammable" : "Grammable (paused)"
        return image
    }
}

/// Small "On-device" / "Cloud" badge so users always know where their text goes.
struct PrivacyBadge: View {
    let backend: BackendID

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: backend.isOnDevice ? "lock.fill" : "cloud.fill")
                .font(.system(size: 8, weight: .bold))
            Text(backend.isOnDevice ? "On-device" : "Cloud")
                .font(.system(size: 9, weight: .semibold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(backend.isOnDevice ? Color.green : Color.blue)
        .background(Capsule().fill((backend.isOnDevice ? Color.green : Color.blue).opacity(0.14)))
        .help(backend.privacyNote)
    }
}
