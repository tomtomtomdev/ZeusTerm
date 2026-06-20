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
}
