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

    /// Discovers repos *per root* so a test can prove a rescan honored the roots it was handed.
    private struct RootsAwareScanner: ProjectScanning {
        var reposByRoot: [String: [URL]]
        var entries: [String: Set<String>]
        func discoverRepositoryURLs(under roots: [URL]) async throws -> [URL] {
            roots.flatMap { reposByRoot[$0.path] ?? [] }
        }
        func rootEntryNames(at repo: URL) throws -> Set<String> { entries[repo.path] ?? [] }
    }

    /// Succeeds until `failNext` is flipped, then throws — lets a test populate the hub and then
    /// fail a later rescan to prove the painted hub survives a transient scan error.
    private final class FlakyScanner: ProjectScanning, @unchecked Sendable {
        var failNext = false
        let repos: [URL]
        let entries: [String: Set<String>]
        init(repos: [URL], entries: [String: Set<String>]) {
            self.repos = repos
            self.entries = entries
        }
        func discoverRepositoryURLs(under roots: [URL]) async throws -> [URL] {
            if failNext { throw StubError.scanFailed }
            return repos
        }
        func rootEntryNames(at repo: URL) throws -> Set<String> { entries[repo.path] ?? [] }
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

    /// Counts how many times a scan ran, so a test can prove a burst of changes coalesced into a
    /// single reconcile (and that an irrelevant change triggered none). Lock-guarded: the loader's
    /// `rescan` runs off the main actor, so the count is mutated off-main and read on-main.
    private final class CountingScanner: ProjectScanning, @unchecked Sendable {
        private let lock = NSLock()
        private var _scanCount = 0
        var scanCount: Int { lock.withLock { _scanCount } }
        let repos: [URL]
        let entries: [String: Set<String>]
        init(repos: [URL], entries: [String: Set<String>]) {
            self.repos = repos
            self.entries = entries
        }
        func discoverRepositoryURLs(under roots: [URL]) async throws -> [URL] {
            lock.withLock { _scanCount += 1 }
            return repos
        }
        func rootEntryNames(at repo: URL) throws -> Set<String> { entries[repo.path] ?? [] }
    }

    /// A watcher whose stream yields canned paths then finishes — finite on purpose so the store's
    /// watch loop terminates and `waitForWatchLoop()` returns deterministically (the real FSEvents
    /// stream is infinite).
    private struct StubWatcher: FileSystemWatching {
        let paths: [String]
        func changes(under roots: [URL]) -> AsyncStream<String> {
            AsyncStream { continuation in
                for path in paths { continuation.yield(path) }
                continuation.finish()
            }
        }
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

    // MARK: - P3-D (roots 2D.1): reload(roots:) — re-scan when the user edits their roots

    @Test func reloadRescansForTheRootsItIsGiven() async {
        let web = URL(fileURLWithPath: "/w/web")
        let scanner = RootsAwareScanner(reposByRoot: ["/w": [web]], entries: ["/w/web": ["package.json"]])
        let store = HubDataStore(
            loader: HubDataLoader(scanner: scanner, git: StubGit(statuses: ["/w/web": .dirty])), roots: [])

        await store.reload(roots: [])                                   // no roots → no repos
        let emptyCount = store.hub?.stars.count ?? 0

        await store.reload(roots: [URL(fileURLWithPath: "/w")])         // now scans /w → finds web
        let populated = try! #require(store.hub)

        #expect(populated.stars.count > emptyCount)
        #expect(populated.stars.contains { $0.name == "web" && !$0.isHub })
    }

    @Test func reloadKeepsTheCurrentHubWhenTheRescanFails() async {
        let web = URL(fileURLWithPath: "/w/web")
        let scanner = FlakyScanner(repos: [web], entries: ["/w/web": ["package.json"]])
        let store = HubDataStore(
            loader: HubDataLoader(scanner: scanner, git: StubGit(statuses: ["/w/web": .dirty])), roots: [])

        await store.reload(roots: [URL(fileURLWithPath: "/w")])         // succeeds → populated
        let populated = store.hub
        #expect(populated?.stars.contains { $0.name == "web" } == true)

        scanner.failNext = true
        await store.reload(roots: [URL(fileURLWithPath: "/w")])         // fails → keep the painted hub

        #expect(store.hub == populated)
    }

    // MARK: - P3-D.3c: live refresh (FSEvents change → relevance filter → debounce → reconcile)

    @Test func aRelevantFileChangeTriggersADebouncedReconcile() async {
        let web = URL(fileURLWithPath: "/w/web")
        let scanner = CountingScanner(repos: [web], entries: ["/w/web": ["package.json"]])
        let store = HubDataStore(
            loader: HubDataLoader(scanner: scanner, git: StubGit(statuses: ["/w/web": .dirty])),
            roots: [URL(fileURLWithPath: "/w")],
            clock: ImmediateClock())

        store.noteChange(at: "/w/web/Sources/main.swift")
        await store.waitForRefresh()

        #expect(scanner.scanCount == 1)
        #expect(store.hub?.stars.contains { $0.name == "web" && !$0.isHub } == true)
    }

    @Test func anIrrelevantChangeUnderAPrunedDirSchedulesNoReconcile() async {
        let scanner = CountingScanner(repos: [URL(fileURLWithPath: "/w/web")], entries: [:])
        let store = HubDataStore(
            loader: HubDataLoader(scanner: scanner, git: StubGit()),
            roots: [URL(fileURLWithPath: "/w")],
            clock: ImmediateClock())

        store.noteChange(at: "/w/web/node_modules/dep/index.js")
        await store.waitForRefresh()   // nothing scheduled → returns immediately

        #expect(scanner.scanCount == 0)
    }

    @Test func aBurstOfRelevantChangesCoalescesIntoASingleReconcile() async {
        let web = URL(fileURLWithPath: "/w/web")
        let scanner = CountingScanner(repos: [web], entries: ["/w/web": ["package.json"]])
        let store = HubDataStore(
            loader: HubDataLoader(scanner: scanner, git: StubGit()),
            roots: [URL(fileURLWithPath: "/w")],
            clock: ImmediateClock())

        // Three synchronous notes: each re-arms the debounce before the prior task can run, so
        // only the last survives → one reconcile, not three.
        store.noteChange(at: "/w/web/a.swift")
        store.noteChange(at: "/w/web/b.swift")
        store.noteChange(at: "/w/web/c.swift")
        await store.waitForRefresh()

        #expect(scanner.scanCount == 1)
    }

    @Test func startWatchingReconcilesWhenTheWatcherReportsARelevantChange() async {
        let web = URL(fileURLWithPath: "/w/web")
        let scanner = CountingScanner(repos: [web], entries: ["/w/web": ["package.json"]])
        let watcher = StubWatcher(paths: ["/w/web/Sources/main.swift"])
        let store = HubDataStore(
            loader: HubDataLoader(scanner: scanner, git: StubGit(statuses: ["/w/web": .dirty])),
            roots: [],
            watcher: watcher,
            clock: ImmediateClock())

        store.startWatching(roots: [URL(fileURLWithPath: "/w")])
        await store.waitForWatchLoop()   // finite stub stream drained → noteChange invoked
        await store.waitForRefresh()     // debounce + reconcile complete

        #expect(scanner.scanCount == 1)
        #expect(store.hub?.stars.contains { $0.name == "web" && !$0.isHub } == true)
    }
}
