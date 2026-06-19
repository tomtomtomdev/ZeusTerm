// swift-tools-version: 6.2
import PackageDescription

// ZeusKit — the testable core of Zeus, consumed by the Xcode app target.
// Clean-architecture layering: ZeusDomain is pure (no framework deps); every other
// target depends inward on ZeusDomain only. External deps (SwiftTerm, GRDB, SwiftGitX)
// are added in their own phases (S1/P5, P3, P2) to keep P0 offline-buildable.
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
    ],
    targets: [
        .target(name: "ZeusDomain"),
        .target(name: "ZeusGit", dependencies: ["ZeusDomain"]),
        .target(name: "ZeusScanner", dependencies: ["ZeusDomain"]),
        .target(name: "ZeusTerminal", dependencies: ["ZeusDomain"]),
        .target(name: "ZeusSuggest", dependencies: ["ZeusDomain"]),
        .target(name: "ZeusUI", dependencies: ["ZeusDomain"]),
        .testTarget(name: "ZeusDomainTests", dependencies: ["ZeusDomain"]),
        .testTarget(name: "ZeusGitTests", dependencies: ["ZeusGit"]),
        .testTarget(name: "ZeusScannerTests", dependencies: ["ZeusScanner"]),
        .testTarget(name: "ZeusSuggestTests", dependencies: ["ZeusSuggest"]),
    ]
)
