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

    /// Proves `cachedHub()` paints from the index alone — touching the disk must crash the test.
    private struct CrashingScanner: ProjectScanning {
        func discoverRepositoryURLs(under roots: [URL]) async throws -> [URL] {
            fatalError("cachedHub must not scan")
        }
        func rootEntryNames(at repo: URL) throws -> Set<String> {
            fatalError("cachedHub must not scan")
        }
    }

    private struct StubGit: GitReading {
        var statuses: [String: GitStatus] = [:]
        var heads: [String: String?] = [:]
        var failingPaths: Set<String> = []
        var headFailingPaths: Set<String> = []
        func status(at url: URL) async throws -> GitStatus {
            if failingPaths.contains(url.path) { throw StubError.statusUnavailable }
            return statuses[url.path] ?? .clean
        }
        func headSHA(at url: URL) async throws -> String? {
            if headFailingPaths.contains(url.path) { throw StubError.headUnavailable }
            return heads[url.path] ?? nil
        }
        // Not exercised by HubDataLoader — fail loudly if the orchestration drifts.
        func readRepository(at url: URL) async throws -> Repository { fatalError("unused") }
        func commits(forBranch: String, in repo: URL, limit: Int, skip: Int) async throws -> [Commit] {
            fatalError("unused")
        }
        func diff(forCommit sha: String, in repo: URL) async throws -> CommitDiff { fatalError("unused") }
    }

    /// Records writes so the rescan's persistence (upsert refresh / remove vanished) is assertable,
    /// while serving `load()` like the real store (merge-by-path, sorted).
    private actor SpyIndexStore: RepositoryIndexStore {
        private var stored: [String: IndexEntry]
        private let failWrites: Bool
        private(set) var upserted: [IndexEntry] = []
        private(set) var removed: [String] = []
        init(stored: [IndexEntry] = [], failWrites: Bool = false) {
            self.stored = Dictionary(uniqueKeysWithValues: stored.map { ($0.path, $0) })
            self.failWrites = failWrites
        }
        func load() async throws -> [IndexEntry] { stored.values.sorted { $0.path < $1.path } }
        func upsert(_ entries: [IndexEntry]) async throws {
            if failWrites { throw StubError.indexWriteFailed }
            upserted.append(contentsOf: entries)
            for e in entries { stored[e.path] = e }
        }
        func remove(paths: [String]) async throws {
            if failWrites { throw StubError.indexWriteFailed }
            removed.append(contentsOf: paths)
            for p in paths { stored[p] = nil }
        }
    }

    private enum StubError: Error { case statusUnavailable, headUnavailable, indexWriteFailed }
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Tests — cachedHub (P3-D.2c: instant cold-start paint from the index)

    @Test func cachedHubBuildsTypedColoredHubFromIndexWithoutScanning() async throws {
        let store = SpyIndexStore(stored: [
            IndexEntry(path: "/work/web", headSHA: "a", type: .frontend, status: .dirty, lastScanned: t0),
            IndexEntry(path: "/work/api", headSHA: "b", type: .backend, status: .clean, lastScanned: t0),
        ])
        // CrashingScanner: cachedHub paints from the index alone, never touching disk.
        let loader = HubDataLoader(scanner: CrashingScanner(), git: StubGit(), index: store)

        let model = try #require(await loader.cachedHub())

        #expect(model.clusters.map(\.type) == ["Frontend", "Backend"])
        let frontend = try #require(model.clusters.first { $0.type == "Frontend" })
        #expect(frontend.members.map(\.name) == ["web"])
        #expect(frontend.members.map(\.status) == [.dirty])     // cached rich payload preserved
        #expect(frontend.members.map(\.id) == ["/work/web"])    // path stays the stable id
    }

    @Test func cachedHubIsNilWithNoIndexOrEmptyCache() async throws {
        let noIndex = HubDataLoader(scanner: StubScanner(repos: [], entries: [:]), git: StubGit())
        #expect(await noIndex.cachedHub() == nil)

        let emptyIndex = HubDataLoader(scanner: StubScanner(repos: [], entries: [:]),
                                       git: StubGit(), index: SpyIndexStore())
        #expect(await emptyIndex.cachedHub() == nil)
    }

    // MARK: - Tests — rescan (P3-D.2c: incremental reconcile + persist against the index)

    @Test func rescanWithEmptyCacheReadsClassifiesAndPersistsEveryRepo() async throws {
        let web = URL(fileURLWithPath: "/work/web")
        let api = URL(fileURLWithPath: "/work/api")
        let scanner = StubScanner(repos: [web, api],
                                  entries: ["/work/web": ["package.json"], "/work/api": ["go.mod"]])
        let git = StubGit(statuses: ["/work/web": .dirty, "/work/api": .clean],
                          heads: ["/work/web": "h1", "/work/api": "h2"])
        let store = SpyIndexStore()
        let loader = HubDataLoader(scanner: scanner, git: git, index: store, now: { self.t0 })

        let model = try await loader.rescan(roots: [URL(fileURLWithPath: "/work")])

        #expect(model.clusters.map(\.type) == ["Frontend", "Backend"])
        // First run → every repo is new → all upserted with their rich payload, nothing removed.
        let upserted = await store.upserted
        #expect(Set(upserted.map(\.path)) == ["/work/web", "/work/api"])
        let webRow = try #require(upserted.first { $0.path == "/work/web" })
        #expect(webRow.headSHA == "h1" && webRow.type == .frontend && webRow.status == .dirty)
        #expect(webRow.lastScanned == t0)
        #expect(await store.removed.isEmpty)
    }

    @Test func rescanReusesUnchangedReposRefreshesMovedAndRemovesVanished() async throws {
        // Cached: a (HEAD ha, rich iOS/ahead), b (HEAD hb-old), c (HEAD hc) — all rich.
        let store = SpyIndexStore(stored: [
            IndexEntry(path: "/w/a", headSHA: "ha", type: .ios, status: .ahead, lastScanned: t0),
            IndexEntry(path: "/w/b", headSHA: "hb-old", type: .frontend, status: .clean, lastScanned: t0),
            IndexEntry(path: "/w/c", headSHA: "hc", type: .backend, status: .dirty, lastScanned: t0),
        ])
        // Disk now: a (HEAD unchanged), b (HEAD moved), d (new). c vanished.
        let a = URL(fileURLWithPath: "/w/a")
        let b = URL(fileURLWithPath: "/w/b")
        let d = URL(fileURLWithPath: "/w/d")
        let scanner = StubScanner(repos: [a, b, d],
                                  entries: ["/w/a": ["App.xcodeproj"], "/w/b": ["package.json"], "/w/d": ["go.mod"]])
        // Deliberately NO status entry for /w/a — if the rescan re-read it, it would fall to .clean.
        let git = StubGit(statuses: ["/w/b": .dirty, "/w/d": .untracked],
                          heads: ["/w/a": "ha", "/w/b": "hb-new", "/w/d": "hd"])
        let loader = HubDataLoader(scanner: scanner, git: git, index: store, now: { self.t0 })

        let model = try await loader.rescan(roots: [])
        let members = model.clusters.flatMap(\.members)

        // a reused from cache: keeps iOS/ahead (proves no re-read — git has no /w/a status).
        let memA = try #require(members.first { $0.id == "/w/a" })
        #expect(memA.status == .ahead)
        // b refreshed: HEAD moved → re-read → now dirty.
        #expect(members.first { $0.id == "/w/b" }?.status == .dirty)
        // d new; c gone.
        #expect(members.contains { $0.id == "/w/d" })
        #expect(!members.contains { $0.id == "/w/c" })

        // Persistence: only the refreshed repos are upserted; only the vanished one is removed.
        #expect(Set(await store.upserted.map(\.path)) == ["/w/b", "/w/d"])
        #expect(await store.removed == ["/w/c"])
    }

    @Test func rescanStillReturnsTheReconciledHubWhenPersistenceFails() async throws {
        let web = URL(fileURLWithPath: "/work/web")
        let scanner = StubScanner(repos: [web], entries: ["/work/web": ["package.json"]])
        let git = StubGit(statuses: ["/work/web": .dirty], heads: ["/work/web": "h1"])
        let store = SpyIndexStore(failWrites: true)
        let loader = HubDataLoader(scanner: scanner, git: git, index: store, now: { self.t0 })

        // A transient index write failure (locked db, disk full) must not blank an already-correct
        // reconcile — the index just stays stale until the next rescan retries.
        let model = try await loader.rescan(roots: [])

        #expect(model.clusters.first?.members.first?.status == .dirty)
    }

    @Test func rescanIsolatesARepoWhoseHeadReadThrows() async throws {
        let ok = URL(fileURLWithPath: "/w/ok")
        let bad = URL(fileURLWithPath: "/w/bad")
        let scanner = StubScanner(repos: [ok, bad],
                                  entries: ["/w/ok": ["go.mod"], "/w/bad": ["package.json"]])
        // `bad`'s HEAD read throws — it must still be discovered + classified (treated as no-HEAD),
        // never aborting the whole rescan.
        let git = StubGit(statuses: ["/w/ok": .clean, "/w/bad": .dirty],
                          heads: ["/w/ok": "h1"], headFailingPaths: ["/w/bad"])
        let loader = HubDataLoader(scanner: scanner, git: git, index: SpyIndexStore(), now: { self.t0 })

        let model = try await loader.rescan(roots: [])
        let members = model.clusters.flatMap(\.members)

        #expect(members.contains { $0.id == "/w/ok" })
        #expect(members.contains { $0.id == "/w/bad" })
    }

    @Test func rescanReusesACommitlessRepoWhoseHeadStaysNil() async throws {
        // Cached commitless repo: nil HEAD, rich payload.
        let store = SpyIndexStore(stored: [
            IndexEntry(path: "/w/fresh", headSHA: nil, type: .macos, status: .untracked, lastScanned: t0),
        ])
        let fresh = URL(fileURLWithPath: "/w/fresh")
        // Still commitless (HEAD nil) and same path → nil == nil → reuse. NO status entry, so a
        // re-read would wrongly drop it to .clean.
        let scanner = StubScanner(repos: [fresh], entries: ["/w/fresh": ["Package.swift"]])
        let git = StubGit(heads: ["/w/fresh": nil])
        let loader = HubDataLoader(scanner: scanner, git: git, index: store, now: { self.t0 })

        let model = try await loader.rescan(roots: [])
        let mem = try #require(model.clusters.flatMap(\.members).first { $0.id == "/w/fresh" })

        #expect(mem.status == .untracked)         // cached payload reused, not re-read
        #expect(await store.upserted.isEmpty)     // reuse → no write
    }

    @Test func rescanReReadsStatusForAHeadUnchangedRepoWithAChangedPathUnderIt() async throws {
        // P3-D.3 finding #2: the working tree flipped clean→dirty without a commit. HEAD is
        // unchanged, so HEAD-only reuse would keep the stale cached `.clean`. A changed path under
        // the repo forces a re-read so the live status surfaces.
        let store = SpyIndexStore(stored: [
            IndexEntry(path: "/w/app", headSHA: "h", type: .frontend, status: .clean, lastScanned: t0),
        ])
        let app = URL(fileURLWithPath: "/w/app")
        let scanner = StubScanner(repos: [app], entries: ["/w/app": ["package.json"]])
        let git = StubGit(statuses: ["/w/app": .dirty], heads: ["/w/app": "h"])   // HEAD unchanged
        let loader = HubDataLoader(scanner: scanner, git: git, index: store, now: { self.t0 })

        let model = try await loader.rescan(roots: [], changedPaths: ["/w/app/Sources/main.swift"])
        let member = try #require(model.clusters.flatMap(\.members).first { $0.id == "/w/app" })

        #expect(member.status == .dirty)                                  // re-read, not the cached clean
        let row = try #require(await store.upserted.first { $0.path == "/w/app" })
        #expect(row.status == .dirty && row.headSHA == "h")               // persisted, HEAD preserved
    }

    @Test func rescanWithoutChangedPathsKeepsTheCachedStatusForAQuietRepo() async throws {
        // No changed path under the repo → the incremental optimization holds: reuse the cached
        // payload, never re-read (git has no status for it, which a re-read would drop to .clean).
        let store = SpyIndexStore(stored: [
            IndexEntry(path: "/w/app", headSHA: "h", type: .frontend, status: .dirty, lastScanned: t0),
        ])
        let app = URL(fileURLWithPath: "/w/app")
        let scanner = StubScanner(repos: [app], entries: ["/w/app": ["package.json"]])
        let git = StubGit(heads: ["/w/app": "h"])                         // HEAD unchanged, no status
        let loader = HubDataLoader(scanner: scanner, git: git, index: store, now: { self.t0 })

        let model = try await loader.rescan(roots: [])                    // no changedPaths
        let member = try #require(model.clusters.flatMap(\.members).first { $0.id == "/w/app" })

        #expect(member.status == .dirty)                                  // cached payload reused
        #expect(await store.upserted.isEmpty)                             // reuse → no write
    }

    // MARK: - Tests — rescan with no index (full-scan path: every repo looks new → classified fresh)

    @Test func rescanWithoutIndexUsesRepoPathAsStableIdSoDuplicateNamesDoNotCollide() async throws {
        let a = URL(fileURLWithPath: "/work/a/api")
        let b = URL(fileURLWithPath: "/work/b/api")
        let scanner = StubScanner(
            repos: [a, b],
            entries: ["/work/a/api": ["go.mod"], "/work/b/api": ["go.mod"]])

        // No index → empty cache → every repo is new → full classify, exactly like the old path.
        let model = try await HubDataLoader(scanner: scanner, git: StubGit()).rescan(roots: [])

        let backend = try #require(model.clusters.first { $0.type == "Backend" })
        #expect(backend.members.count == 2)
        #expect(Set(backend.members.map(\.id)) == ["/work/a/api", "/work/b/api"])
        #expect(backend.members.allSatisfy { $0.name == "api" })
        #expect(model.hub.name == "All Projects")
    }

    @Test func rescanWithoutIndexIsResilientWhenOneReposStatusFails() async throws {
        let ok = URL(fileURLWithPath: "/work/ok")
        let broken = URL(fileURLWithPath: "/work/broken")
        let scanner = StubScanner(
            repos: [ok, broken],
            entries: ["/work/ok": ["go.mod"], "/work/broken": ["go.mod"]])
        // `broken`'s status read throws — the rescan must still surface both repos.
        let git = StubGit(statuses: ["/work/ok": .ahead], failingPaths: ["/work/broken"])

        let model = try await HubDataLoader(scanner: scanner, git: git).rescan(roots: [])

        let backend = try #require(model.clusters.first { $0.type == "Backend" })
        #expect(backend.members.count == 2)
        let brokenMember = try #require(backend.members.first { $0.id == "/work/broken" })
        #expect(brokenMember.status == .clean)     // neutral fallback, not a crash
    }
}
