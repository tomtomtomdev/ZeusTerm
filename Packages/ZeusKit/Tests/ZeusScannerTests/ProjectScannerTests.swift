import Testing
import Foundation
@testable import ZeusScanner

struct ProjectScannerTests {

    @Test func findsRepositoriesAndPrunesHeavyDirectories() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("zeus-scan-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }

        // A real repo.
        let repo = root.appendingPathComponent("myrepo")
        try fm.createDirectory(at: repo.appendingPathComponent(".git"),
                               withIntermediateDirectories: true)
        // A nested .git inside node_modules that MUST be pruned (not reported).
        try fm.createDirectory(at: repo.appendingPathComponent("node_modules/dep/.git"),
                               withIntermediateDirectories: true)

        let found = try await ProjectScanner().discoverRepositoryURLs(under: [root])

        #expect(found.map(\.lastPathComponent).contains("myrepo"))
        #expect(!found.contains { $0.path.contains("node_modules") })
    }

    @Test func doesNotIndexRepositoriesNestedInsideADiscoveredRepo() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("zeus-nested-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }

        // A real top-level repo.
        let repo = root.appendingPathComponent("myapp")
        try fm.createDirectory(at: repo.appendingPathComponent(".git"),
                               withIntermediateDirectories: true)
        // A vendored dependency repo nested in the app's build output. `build` is NOT in the
        // pruned set, yet a repo's internals (deps, submodules, build artifacts) must never be
        // indexed as separate top-level projects. Regression: a SwiftPM checkout under
        // <repo>/build/SourcePackages/checkouts was surfacing as its own "swift-collections" repo.
        try fm.createDirectory(
            at: repo.appendingPathComponent("build/SourcePackages/checkouts/swift-collections/.git"),
            withIntermediateDirectories: true)

        let found = try await ProjectScanner().discoverRepositoryURLs(under: [root])

        #expect(found.map(\.lastPathComponent) == ["myapp"])
        #expect(!found.contains { $0.path.contains("swift-collections") })
    }

    @Test func doesNotIndexRepositoriesNestedInsideARepoThatIsItselfAScanRoot() async throws {
        let fm = FileManager.default
        // The scan root is ITSELF a repo (the user configured a single project as a root).
        let repo = fm.temporaryDirectory.appendingPathComponent("zeus-ownroot-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: repo) }
        try fm.createDirectory(at: repo.appendingPathComponent(".git"),
                               withIntermediateDirectories: true)
        // A vendored SwiftPM checkout under the root's build output. `build` is NOT in the pruned
        // set, so the walk would descend and mis-index it. Regression: 4b106aa only pruned repos
        // discovered as SUBDIRECTORIES; a repo configured as its own root still had build/ walked.
        try fm.createDirectory(
            at: repo.appendingPathComponent("build/SourcePackages/checkouts/swift-collections/.git"),
            withIntermediateDirectories: true)

        let found = try await ProjectScanner().discoverRepositoryURLs(under: [repo])

        // The root repo owns its whole subtree — it is the only project, nothing nested leaks.
        #expect(found.map(\.lastPathComponent) == [repo.lastPathComponent])
        #expect(!found.contains { $0.path.contains("swift-collections") })
    }

    @Test func listsRootEntryNamesForClassification() throws {
        let fm = FileManager.default
        let repo = fm.temporaryDirectory.appendingPathComponent("zeus-entries-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: repo) }
        try fm.createDirectory(at: repo.appendingPathComponent(".git"),
                               withIntermediateDirectories: true)
        try fm.createDirectory(at: repo.appendingPathComponent("Sources"),
                               withIntermediateDirectories: true)
        try "{}".write(to: repo.appendingPathComponent("package.json"),
                       atomically: true, encoding: .utf8)

        let entries = try ProjectScanner().rootEntryNames(at: repo)

        // Shallow listing of the repo root — the marker names RepoClassifier matches on.
        #expect(entries.contains("package.json"))
        #expect(entries.contains("Sources"))
        #expect(entries.contains(".git"))
        // Does not descend: nested children are not surfaced.
        #expect(!entries.contains("main.swift"))
    }

    @Test func defaultDevRootsKeepsOnlyExistingSpecFolders() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("zeus-home-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: home) }
        // Only two of the SPEC §2.1 dev roots actually exist under this home.
        try fm.createDirectory(at: home.appendingPathComponent("Developer"),
                               withIntermediateDirectories: true)
        try fm.createDirectory(at: home.appendingPathComponent("Code"),
                               withIntermediateDirectories: true)

        let roots = ProjectScanner.defaultDevRoots(home: home, fileManager: fm)

        #expect(Set(roots.map(\.lastPathComponent)) == ["Developer", "Code"])
        // Non-existent SPEC roots (Projects, src, work, git, Documents) are pruned.
        #expect(!roots.contains { $0.lastPathComponent == "Projects" })
    }

    @Test func defaultDevRootsIncludesDesktopWhenItExists() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("zeus-home-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: home) }
        // ~/Desktop is a common dev root (the user keeps repos there), so it must be scanned.
        try fm.createDirectory(at: home.appendingPathComponent("Desktop"),
                               withIntermediateDirectories: true)

        let roots = ProjectScanner.defaultDevRoots(home: home, fileManager: fm)

        #expect(roots.contains { $0.lastPathComponent == "Desktop" })
    }
}
