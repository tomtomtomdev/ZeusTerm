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
        .library(name: "ZeusTerminal", targets: ["ZeusTerminal"]),
        .library(name: "ZeusSuggest", targets: ["ZeusSuggest"]),
        .library(name: "ZeusUI", targets: ["ZeusUI"]),
        // S1 spike harness — a tiny throwaway GUI app that embeds a live PTY.
        // `swift run S1TerminalSpike` to prove SwiftTerm reflow + truecolor (SPEC §4).
        .executable(name: "S1TerminalSpike", targets: ["S1TerminalSpike"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.13.0"),
    ],
    targets: [
        .target(name: "ZeusDomain"),
        .target(name: "ZeusGit", dependencies: ["ZeusDomain"]),
        .target(name: "ZeusScanner", dependencies: ["ZeusDomain"]),
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
        .testTarget(name: "ZeusDomainTests", dependencies: ["ZeusDomain"]),
        .testTarget(name: "ZeusGitTests", dependencies: ["ZeusGit"]),
        .testTarget(name: "ZeusScannerTests", dependencies: ["ZeusScanner"]),
        .testTarget(name: "ZeusTerminalTests", dependencies: ["ZeusTerminal"]),
        .testTarget(name: "ZeusSuggestTests", dependencies: ["ZeusSuggest"]),
        .testTarget(name: "ZeusUITests", dependencies: ["ZeusUI"]),
    ]
)
