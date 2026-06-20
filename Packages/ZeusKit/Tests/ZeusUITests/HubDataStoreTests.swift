import Testing
import Foundation
import ZeusDomain
@testable import ZeusUI

/// P3-C.2: the UI-side store that drives the real Hub level. It runs the pure `HubDataLoader`
/// (off-main) and publishes the laid-out `ConstellationHub` the view renders. Tested with stub
/// ports so it stays a fast unit test — no disk, no git.
@MainActor
struct HubDataStoreTests {

    private struct StubScanner: ProjectScanning {
        var repos: [URL]
        var entries: [String: Set<String>]
        func discoverRepositoryURLs(under roots: [URL]) async throws -> [URL] { repos }
        func rootEntryNames(at repo: URL) throws -> Set<String> { entries[repo.path] ?? [] }
    }

    private struct StubGit: GitReading {
        var statuses: [String: GitStatus] = [:]
        var heads: [String: String?] = [:]
        func status(at url: URL) async throws -> GitStatus { statuses[url.path] ?? .clean }
        func headSHA(at url: URL) async throws -> String? { heads[url.path] ?? nil }
        func readRepository(at url: URL) async throws -> Repository { fatalError("unused") }
        func commits(forBranch: String, in repo: URL, limit: Int, skip: Int) async throws -> [Commit] {
            fatalError("unused")
        }
        func diff(forCommit sha: String, in repo: URL) async throws -> CommitDiff { fatalError("unused") }
    }

    private struct FailingScanner: ProjectScanning {
        func discoverRepositoryURLs(under roots: [URL]) async throws -> [URL] { throw StubError.scanFailed }
        func rootEntryNames(at repo: URL) throws -> Set<String> { [] }
    }

    /// In-memory index that serves canned cached entries — enough to exercise the store's
    /// cold-start paint; writes are no-ops (the loader's persistence is covered in ZeusDomain).
    private actor StubIndex: RepositoryIndexStore {
        private let entries: [IndexEntry]
        init(_ entries: [IndexEntry] = []) { self.entries = entries }
        func load() async throws -> [IndexEntry] { entries }
        func upsert(_ entries: [IndexEntry]) async throws {}
        func remove(paths: [String]) async throws {}
    }

    private enum StubError: Error { case scanFailed }
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> HubDataStore {
        let scanner = StubScanner(repos: [URL(fileURLWithPath: "/w/web")],
                                  entries: ["/w/web": ["package.json"]])
        let git = StubGit(statuses: ["/w/web": .dirty])
        return HubDataStore(loader: HubDataLoader(scanner: scanner, git: git), roots: [])
    }

    @Test func hubIsNilBeforeLoad() {
        #expect(makeStore().hub == nil)
    }

    @Test func loadPublishesLaidOutHubFromScannedRepos() async {
        let store = makeStore()
        await store.load()

        let hub = try! #require(store.hub)
        #expect(hub.stars.contains { $0.isHub && $0.name == "All Projects" })
        #expect(hub.stars.contains { $0.name == "web" && $0.status == .dirty && !$0.isHub })
    }

    @Test func loadShowsEmptyHubWhenScanFailsRatherThanSpinningForever() async {
        let store = HubDataStore(
            loader: HubDataLoader(scanner: FailingScanner(), git: StubGit()), roots: [])
        await store.load()

        // A failed scan publishes an empty hub (just the central star) so the scanning
        // indicator clears — never a permanent nil/spinner.
        let hub = try! #require(store.hub)
        #expect(hub.stars.allSatisfy { $0.isHub })
        #expect(hub.stars.count == 1)
    }

    // MARK: - P3-D.2c.2b: two-phase paint (cached cold-start → live reconcile)

    @Test func loadKeepsTheCachedPaintWhenTheLiveRescanCannotReachDisk() async {
        // The index has a repo; the live scan fails. The cached paint must survive — proving the
        // store painted from the index first, not just the (failed) live scan.
        let index = StubIndex([
            IndexEntry(path: "/w/api", headSHA: "x", type: .backend, status: .clean, lastScanned: t0),
        ])
        let store = HubDataStore(
            loader: HubDataLoader(scanner: FailingScanner(), git: StubGit(), index: index), roots: [])
        await store.load()

        let hub = try! #require(store.hub)
        #expect(hub.stars.contains { $0.name == "api" && !$0.isHub })
    }

    @Test func loadReplacesTheStaleCacheWithTheLiveReconcile() async {
        // Cache says api is clean at an old HEAD; disk says it moved and is now dirty.
        let index = StubIndex([
            IndexEntry(path: "/w/api", headSHA: "old", type: .backend, status: .clean, lastScanned: t0),
        ])
        let scanner = StubScanner(repos: [URL(fileURLWithPath: "/w/api")], entries: ["/w/api": ["go.mod"]])
        let git = StubGit(statuses: ["/w/api": .dirty], heads: ["/w/api": "new"])
        let store = HubDataStore(
            loader: HubDataLoader(scanner: scanner, git: git, index: index), roots: [])
        await store.load()

        let hub = try! #require(store.hub)
        // Final published state is the live reconcile (dirty), not the stale cached clean.
        #expect(hub.stars.contains { $0.name == "api" && $0.status == .dirty })
    }
}
