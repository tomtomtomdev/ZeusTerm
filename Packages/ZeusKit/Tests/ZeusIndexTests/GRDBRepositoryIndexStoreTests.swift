import Testing
import Foundation
import GRDB
import ZeusDomain
@testable import ZeusIndex

/// P3-D.2b — the GRDB/SQLite adapter implementing `RepositoryIndexStore`. Exercised against a
/// fresh in-memory database per test (no disk, deterministic), characterizing the real SQLite
/// round-trip: persistence, upsert-by-path, nil headSHA, and removal.
///
/// Test List:
///  [x] fresh store loads empty
///  [x] upsert then load round-trips every field, sorted by path
///  [x] upsert on an existing path updates in place (no duplicate row)
///  [x] nil headSHA round-trips as nil
///  [x] remove drops only the named paths
///  [x] remove([]) is a no-op (doesn't wipe the table)
///  [x] upsert round-trips RepoType + GitStatus (the cached rich payload)
///  [x] a db written by the D.2b (pre-rich) schema migrates in place without data loss
struct GRDBRepositoryIndexStoreTests {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func entry(_ path: String,
                       head: String?,
                       type: RepoType = .other,
                       status: GitStatus = .clean,
                       scannedOffset: TimeInterval = 0) -> IndexEntry {
        IndexEntry(path: path, headSHA: head, type: type, status: status,
                   lastScanned: t0.addingTimeInterval(scannedOffset))
    }

    @Test func freshStoreLoadsEmpty() async throws {
        let store = try GRDBRepositoryIndexStore()
        let loaded = try await store.load()
        #expect(loaded.isEmpty)
    }

    @Test func upsertThenLoadRoundTripsEntriesSortedByPath() async throws {
        let store = try GRDBRepositoryIndexStore()
        let web = entry("/dev/web", head: "aaa")
        let api = entry("/dev/api", head: "bbb")

        try await store.upsert([web, api])
        let loaded = try await store.load()

        // ORDER BY path → api before web.
        #expect(loaded == [api, web])
    }

    @Test func upsertOnExistingPathUpdatesInPlace() async throws {
        let store = try GRDBRepositoryIndexStore()
        try await store.upsert([entry("/dev/app", head: "old", scannedOffset: 0)])

        try await store.upsert([entry("/dev/app", head: "new", scannedOffset: 3600)])
        let loaded = try await store.load()

        #expect(loaded.count == 1)
        #expect(loaded.first?.headSHA == "new")
        #expect(loaded.first?.lastScanned == t0.addingTimeInterval(3600))
    }

    @Test func nilHeadSHARoundTripsAsNil() async throws {
        let store = try GRDBRepositoryIndexStore()
        try await store.upsert([entry("/dev/fresh", head: nil)])

        let loaded = try await store.load()

        #expect(loaded.count == 1)
        #expect(loaded.first?.headSHA == nil)
    }

    @Test func removeDropsOnlyNamedPaths() async throws {
        let store = try GRDBRepositoryIndexStore()
        try await store.upsert([entry("/dev/a", head: "1"),
                                entry("/dev/b", head: "2"),
                                entry("/dev/c", head: "3")])

        try await store.remove(paths: ["/dev/a", "/dev/c"])
        let loaded = try await store.load()

        #expect(loaded.map(\.path) == ["/dev/b"])
    }

    @Test func removeEmptyIsANoOp() async throws {
        let store = try GRDBRepositoryIndexStore()
        try await store.upsert([entry("/dev/keep", head: "1")])

        try await store.remove(paths: [])
        let loaded = try await store.load()

        #expect(loaded.map(\.path) == ["/dev/keep"])
    }

    @Test func upsertRoundTripsRepoTypeAndStatus() async throws {
        let store = try GRDBRepositoryIndexStore()
        let api = entry("/dev/api", head: "abc", type: .backend, status: .dirty)

        try await store.upsert([api])
        let loaded = try await store.load()

        // Full-value equality: a store that drops type/status would return the
        // neutral .other/.clean defaults and fail this.
        #expect(loaded == [api])
    }

    @Test func migratesADatabaseWrittenByTheOlderSchema() async throws {
        // A db file as the D.2b adapter would have left it: repo_index without type/status,
        // and no GRDB migration bookkeeping.
        let path = NSTemporaryDirectory() + "zeus-index-migration-\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }
        do {
            let legacy = try DatabaseQueue(path: path)
            try await legacy.write { db in
                try db.execute(sql: """
                    CREATE TABLE repo_index (
                        path TEXT PRIMARY KEY NOT NULL,
                        head_sha TEXT,
                        last_scanned DOUBLE NOT NULL
                    )
                    """)
                try db.execute(sql: "INSERT INTO repo_index (path, head_sha, last_scanned) VALUES (?, ?, ?)",
                               arguments: ["/dev/legacy", "old", t0.timeIntervalSince1970])
            }
        }

        // Reopening with the current store must add the columns in place (not crash), and keep
        // the old row, defaulting its type/status to neutral.
        let store = try GRDBRepositoryIndexStore(path: path)
        let loaded = try await store.load()

        #expect(loaded == [entry("/dev/legacy", head: "old", type: .other, status: .clean)])
    }
}
