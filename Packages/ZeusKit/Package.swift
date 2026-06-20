// swift-tools-version: 6.2
import PackageDescription

// ZeusKit — the testable core of Zeus, consumed by the Xcode app target.
// Clean-architecture layering: ZeusDomain is pure (no framework deps); every other
// target depends inward on ZeusDomain only. External deps are added in their own
// phases to keep earlier phases offline-buildable:
//   - SwiftTerm  → S1 spike / P5 (terminal)   [added now]
//   - GRDB       → P3 (scan index)
//   - SwiftGitX  → P2 (git reads)
let package = Package(
    name: "ZeusKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ZeusDomain", targets: ["ZeusDomain"]),
        .library(name: "ZeusGit", targets: ["ZeusGit"]),
        .library(name: "ZeusScanner", targets: ["ZeusScanner"]),
        .library(name: "ZeusIndex", targets: ["ZeusIndex"]),
        .library(name: "ZeusTerminal", targets: ["ZeusTerminal"]),
        .library(name: "ZeusSuggest", targets: ["ZeusSuggest"]),
        .library(name: "ZeusUI", targets: ["ZeusUI"]),
        // S1 spike harness — a tiny throwaway GUI app that embeds a live PTY.
        // `swift run S1TerminalSpike` to prove SwiftTerm reflow + truecolor (SPEC §4).
        .executable(name: "S1TerminalSpike", targets: ["S1TerminalSpike"]),
        // P4 zoom-feel harness (roadmap item A.5) — shows the full ConstellationShell so the
        // powers-of-ten zoom can be felt/tuned by eye. `swift run ZoomSpike`. (Distinct from
        // SPEC §4's "S2 = right-arrow accept" spike; this one is about the §7 zoom motion.)
        .executable(name: "ZoomSpike", targets: ["ZoomSpike"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.13.0"),
        // GRDB → P3-D scan index (SPEC §167). Isolated in the ZeusIndex target so scanner/
        // domain consumers don't transitively link SQLite (Common-Reuse Principle).
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    ],
    targets: [
        .target(name: "ZeusDomain"),
        .target(name: "ZeusGit", dependencies: ["ZeusDomain"]),
        .target(name: "ZeusScanner", dependencies: ["ZeusDomain"]),
        .target(
            name: "ZeusIndex",
            dependencies: [
                "ZeusDomain",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .target(
            name: "ZeusTerminal",
            dependencies: [
                "ZeusDomain",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ]
        ),
        .target(name: "ZeusSuggest", dependencies: ["ZeusDomain"]),
        .target(name: "ZeusUI", dependencies: ["ZeusDomain"]),
        .executableTarget(
            name: "S1TerminalSpike",
            dependencies: ["ZeusTerminal", "ZeusUI"]
        ),
        .executableTarget(
            name: "ZoomSpike",
            dependencies: ["ZeusUI", "ZeusTerminal"]
        ),
        .testTarget(name: "ZeusDomainTests", dependencies: ["ZeusDomain"]),
        .testTarget(name: "ZeusGitTests", dependencies: ["ZeusGit"]),
        .testTarget(name: "ZeusScannerTests", dependencies: ["ZeusScanner"]),
        .testTarget(
            name: "ZeusIndexTests",
            dependencies: [
                "ZeusIndex",
                // Direct GRDB dep so the migration test can write a pre-migration (legacy) schema.
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(name: "ZeusTerminalTests", dependencies: ["ZeusTerminal"]),
        .testTarget(name: "ZeusSuggestTests", dependencies: ["ZeusSuggest"]),
        .testTarget(name: "ZeusUITests", dependencies: ["ZeusUI"]),
    ]
)
