#!/usr/bin/env swift
// Renders the Grammable app icon (1024×1024 PNG) with CoreGraphics — no design tools needed.
// Usage: swift scripts/make-icon.swift <output.png>
// Grammable — Copyright (C) 2026 Udaya Lakmal — GPL-3.0-or-later

import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let S: CGFloat = 1024

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let space = CGColorSpaceCreateDeviceRGB()

// macOS Big Sur+ icon grid: 824pt rounded square centred in 1024 with a soft shadow.
let inset: CGFloat = 100
let tile = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
let radius: CGFloat = 185
let tilePath = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: color(0x1E1050, 0.30))
ctx.addPath(tilePath)
ctx.setFillColor(color(0x4F46E5))
ctx.fillPath()
ctx.restoreGState()

// Background gradient: indigo → violet → pink.
ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
let bg = CGGradient(colorsSpace: space,
                    colors: [color(0x4338CA), color(0x9333EA), color(0xEC4899)] as CFArray,
                    locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])

// Soft glow top-left for depth.
let glow = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.28), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: tile.minX + 200, y: tile.maxY - 160), startRadius: 0,
                       endCenter: CGPoint(x: tile.minX + 200, y: tile.maxY - 160), endRadius: 560, options: [])
ctx.restoreGState()

// The "G": a thick rounded arc with a crossbar that ends in a checkmark tick.
let center = CGPoint(x: S / 2 - 18, y: S / 2 - 6)
let r: CGFloat = 236
let stroke: CGFloat = 96

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: color(0x2A0A5E, 0.45))
ctx.setStrokeColor(color(0xFFFFFF))
ctx.setLineWidth(stroke)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)

let g = CGMutablePath()
// Arc from the upper-right opening, counter-clockwise around to the lower right.
g.addArc(center: center, radius: r, startAngle: .pi * 0.25, endAngle: -.pi * 0.08, clockwise: false)
ctx.addPath(g)
ctx.strokePath()

// Crossbar turning into a check mark: starts inside the G, dips, then flicks up and out.
let check = CGMutablePath()
check.move(to: CGPoint(x: center.x + 20, y: center.y - 8))
check.addLine(to: CGPoint(x: center.x + 118, y: center.y - 96))
check.addLine(to: CGPoint(x: center.x + 330, y: center.y + 150))
ctx.addPath(check)
ctx.strokePath()
ctx.restoreGState()

// Sparkle (four-point star) at top-right: the "AI" hint.
func sparkle(at c: CGPoint, size r: CGFloat, waist: CGFloat, fill: CGColor) {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: c.x, y: c.y + r))
    p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + waist, y: c.y + waist))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x + waist, y: c.y - waist))
    p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - waist, y: c.y - waist))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x - waist, y: c.y + waist))
    ctx.addPath(p)
    ctx.setFillColor(fill)
    ctx.fillPath()
}
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 30, color: color(0xFFF7AE, 0.9))
sparkle(at: CGPoint(x: 742, y: 748), size: 92, waist: 14, fill: color(0xFFF3B0))
sparkle(at: CGPoint(x: 846, y: 826), size: 32, waist: 7, fill: color(0xFFFFFF, 0.95))
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
