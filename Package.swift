// swift-tools-version:5.9
// Grammable — free, open-source, AI grammar & rewrite assistant for macOS.
// Copyright (C) 2026 Udaya Lakmal. Licensed under GPL-3.0-or-later.

import PackageDescription

let package = Package(
    name: "Grammable",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Grammable", targets: ["Grammable"]),
        .library(name: "GrammableCore", targets: ["GrammableCore"]),
    ],
    targets: [
        // Pure logic: presets, diffing, prompt building and AI backends. No AppKit.
        .target(
            name: "GrammableCore",
            path: "Sources/GrammableCore"
        ),
        // The menu bar app: selection detection, floating UI, settings.
        .executableTarget(
            name: "Grammable",
            dependencies: ["GrammableCore"],
            path: "Sources/Grammable"
        ),
        .testTarget(
            name: "GrammableTests",
            dependencies: ["GrammableCore"],
            path: "Tests/GrammableTests"
        ),
    ]
)
