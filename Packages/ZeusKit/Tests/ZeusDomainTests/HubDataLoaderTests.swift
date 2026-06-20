import Testing
import Foundation
@testable import ZeusDomain

/// P3-C.1: the pure orchestration use case that turns scan roots into a `HubModel` by wiring
/// the `ProjectScanning` + `GitReading` ports through `RepoClassifier` + `HubModelBuilder`.
/// Tested with hand-written Stubs so it stays a fast, deterministic unit test (no disk, no git).
struct HubDataLoaderTests {

    // MARK: - Test Stubs (canned indirect inputs; unused git methods are Crash Test Dummies)

    private struct StubScanner: ProjectScanning {
        var repos: [URL]
        var entries: [String: Set<String>]
        func discoverRepositoryURLs(under roots: [URL]) async throws -> [URL] { repos }
        func rootEntryNames(at repo: URL) throws -> Set<String> { entries[repo.path] ?? [] }
    }

    private struct StubGit: GitReading {
        var statuses: [String: GitStatus] = [:]
        var failingPaths: Set<String> = []
        func status(at url: URL) async throws -> GitStatus {
            if failingPaths.contains(url.path) { throw StubError.statusUnavailable }
            return statuses[url.path] ?? .clean
        }
        // Not exercised by HubDataLoader — fail loudly if the orchestration drifts.
        func readRepository(at url: URL) async throws -> Repository { fatalError("unused") }
        func commits(forBranch: String, in repo: URL, limit: Int, skip: Int) async throws -> [Commit] {
            fatalError("unused")
        }
        func diff(forCommit sha: String, in repo: URL) async throws -> CommitDiff { fatalError("unused") }
    }

    private enum StubError: Error { case statusUnavailable }

    // MARK: - Tests

    @Test func loadClassifiesAndStatusesReposIntoHubModelClusters() async throws {
        let web = URL(fileURLWithPath: "/work/web")
        let api = URL(fileURLWithPath: "/work/api")
        let scanner = StubScanner(
            repos: [web, api],
            entries: ["/work/web": ["package.json"], "/work/api": ["go.mod"]])
        let git = StubGit(statuses: ["/work/web": .dirty, "/work/api": .clean])

        let model = try await HubDataLoader(scanner: scanner, git: git)
            .load(roots: [URL(fileURLWithPath: "/work")])

        // package.json → Frontend, go.mod → Backend (canonical order).
        #expect(model.clusters.map(\.type) == ["Frontend", "Backend"])
        let frontend = try #require(model.clusters.first { $0.type == "Frontend" })
        #expect(frontend.members.map(\.name) == ["web"])
        #expect(frontend.members.map(\.status) == [.dirty])
        let backend = try #require(model.clusters.first { $0.type == "Backend" })
        #expect(backend.members.map(\.status) == [.clean])
        #expect(model.hub.name == "All Projects")
    }

    @Test func loadUsesRepoPathAsStableIdSoDuplicateNamesDoNotCollide() async throws {
        let a = URL(fileURLWithPath: "/work/a/api")
        let b = URL(fileURLWithPath: "/work/b/api")
        let scanner = StubScanner(
            repos: [a, b],
            entries: ["/work/a/api": ["go.mod"], "/work/b/api": ["go.mod"]])

        let model = try await HubDataLoader(scanner: scanner, git: StubGit()).load(roots: [])

        let backend = try #require(model.clusters.first { $0.type == "Backend" })
        #expect(backend.members.count == 2)
        #expect(Set(backend.members.map(\.id)) == ["/work/a/api", "/work/b/api"])
        #expect(backend.members.allSatisfy { $0.name == "api" })
    }

    @Test func loadIsResilientWhenOneReposStatusFails() async throws {
        let ok = URL(fileURLWithPath: "/work/ok")
        let broken = URL(fileURLWithPath: "/work/broken")
        let scanner = StubScanner(
            repos: [ok, broken],
            entries: ["/work/ok": ["go.mod"], "/work/broken": ["go.mod"]])
        // `broken`'s status read throws — the load must still surface both repos.
        let git = StubGit(statuses: ["/work/ok": .ahead], failingPaths: ["/work/broken"])

        let model = try await HubDataLoader(scanner: scanner, git: git).load(roots: [])

        let backend = try #require(model.clusters.first { $0.type == "Backend" })
        #expect(backend.members.count == 2)
        let brokenMember = try #require(backend.members.first { $0.id == "/work/broken" })
        #expect(brokenMember.status == .clean)     // neutral fallback, not a crash
    }
}
