import Testing
import Foundation
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
struct GRDBRepositoryIndexStoreTests {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func entry(_ path: String, head: String?, scannedOffset: TimeInterval = 0) -> IndexEntry {
        IndexEntry(path: path, headSHA: head, lastScanned: t0.addingTimeInterval(scannedOffset))
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
}
