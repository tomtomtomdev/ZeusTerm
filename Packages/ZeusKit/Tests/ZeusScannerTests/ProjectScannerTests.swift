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
}
