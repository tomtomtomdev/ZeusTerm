import Foundation
import Testing
@testable import ZeusDomain

/// P3-D (roots, Slice 2A) — the pure rule that turns the user's *configured* scan roots
/// (persisted path strings in `ZeusSettings.scanRoots`) into the URLs the scanner should walk.
///
/// Contract:
///   • no configured roots → fall back to the supplied defaults (so the Hub is never empty
///     just because the user hasn't customised anything)
///   • any configured roots → use them, keeping only the paths that still exist as directories
///     (a deleted/renamed folder must never error the walk — same rule as `defaultDevRoots`)
///
/// Pure: the only side-effect is a `FileManager` existence check (injected for testability).
///
/// Test List:
///  [x] empty configured              → returns the defaults unchanged
///  [x] configured (all existing)     → returns those as file URLs, order preserved
///  [x] configured with a missing path → that path is dropped
struct ScanRootResolverTests {

    /// Makes `count` real temp directories and returns their paths; cleaned up by the caller's defer.
    private func makeDirs(_ count: Int, cleanup: inout [URL]) throws -> [String] {
        let fm = FileManager.default
        var paths: [String] = []
        for _ in 0..<count {
            let dir = fm.temporaryDirectory.appendingPathComponent("zeus-root-\(UUID().uuidString)")
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            cleanup.append(dir)
            paths.append(dir.path)
        }
        return paths
    }

    @Test func emptyConfiguredFallsBackToDefaults() {
        let defaults = [URL(fileURLWithPath: "/dev/a"), URL(fileURLWithPath: "/dev/b")]

        let roots = ScanRootResolver.effectiveRoots(configured: [], defaults: defaults)

        #expect(roots == defaults)
    }

    @Test func configuredRootsOverrideDefaultsInOrder() throws {
        var cleanup: [URL] = []
        defer { cleanup.forEach { try? FileManager.default.removeItem(at: $0) } }
        let paths = try makeDirs(2, cleanup: &cleanup)

        let roots = ScanRootResolver.effectiveRoots(
            configured: paths,
            defaults: [URL(fileURLWithPath: "/should/be/ignored")])

        #expect(roots.map(\.path) == paths)
    }

    @Test func nonExistentConfiguredPathsAreDropped() throws {
        var cleanup: [URL] = []
        defer { cleanup.forEach { try? FileManager.default.removeItem(at: $0) } }
        let real = try makeDirs(1, cleanup: &cleanup)[0]
        let ghost = FileManager.default.temporaryDirectory
            .appendingPathComponent("zeus-gone-\(UUID().uuidString)").path

        let roots = ScanRootResolver.effectiveRoots(configured: [real, ghost], defaults: [])

        #expect(roots.map(\.path) == [real])
    }
}
