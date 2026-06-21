import Testing
import Foundation
import ZeusDomain
@testable import ZeusUI

/// P3-D (roots, Slice 2C) — the UDF feature store behind the settings UI. It owns the editable
/// `ZeusSettings`, mutates `scanRoots` through explicit intents (add/remove/reset), and persists
/// each change through the injected `SettingsStoring` port. Kept separate from HubDataStore so
/// neither becomes a god store. Tested with an in-memory fake — no SwiftData, no disk.
///
/// Test List:
///  [x] init paints the persisted roots
///  [x] init survives a failing load → empty roots, no crash
///  [x] addRoot appends and persists
///  [x] addRoot ignores a duplicate (no second copy, no extra write)
///  [x] removeRoot drops the path and persists
///  [x] resetRoots clears every configured root and persists
@MainActor
struct SettingsStoreTests {

    /// In-memory `SettingsStoring` fake that records writes. `@unchecked Sendable` is the test-double
    /// escape hatch (mutable state, only ever touched on the @MainActor test).
    private final class FakeSettingsStore: SettingsStoring, @unchecked Sendable {
        var stored: ZeusSettings
        private(set) var saveCount = 0
        var loadError: Error?
        init(_ initial: ZeusSettings = ZeusSettings()) { stored = initial }
        func load() throws -> ZeusSettings {
            if let loadError { throw loadError }
            return stored
        }
        func save(_ settings: ZeusSettings) throws { stored = settings; saveCount += 1 }
    }

    private enum StubError: Error { case loadFailed }

    @Test func initPaintsThePersistedRoots() {
        let backing = FakeSettingsStore(ZeusSettings(scanRoots: ["/Users/me/Desktop"]))

        let store = SettingsStore(store: backing)

        #expect(store.scanRoots == ["/Users/me/Desktop"])
    }

    @Test func initSurvivesAFailingLoad() {
        let backing = FakeSettingsStore()
        backing.loadError = StubError.loadFailed

        let store = SettingsStore(store: backing)

        #expect(store.scanRoots.isEmpty)
    }

    @Test func addRootAppendsAndPersists() {
        let backing = FakeSettingsStore()
        let store = SettingsStore(store: backing)

        store.addRoot("/Users/me/work")

        #expect(store.scanRoots == ["/Users/me/work"])
        #expect(backing.stored.scanRoots == ["/Users/me/work"])
        #expect(backing.saveCount == 1)
    }

    @Test func addRootIgnoresADuplicate() {
        let backing = FakeSettingsStore(ZeusSettings(scanRoots: ["/a"]))
        let store = SettingsStore(store: backing)

        store.addRoot("/a")

        #expect(store.scanRoots == ["/a"])
        #expect(backing.saveCount == 0)
    }

    @Test func removeRootDropsThePathAndPersists() {
        let backing = FakeSettingsStore(ZeusSettings(scanRoots: ["/a", "/b"]))
        let store = SettingsStore(store: backing)

        store.removeRoot("/a")

        #expect(store.scanRoots == ["/b"])
        #expect(backing.stored.scanRoots == ["/b"])
        #expect(backing.saveCount == 1)
    }

    @Test func resetRootsClearsEveryConfiguredRoot() {
        let backing = FakeSettingsStore(ZeusSettings(scanRoots: ["/a", "/b"]))
        let store = SettingsStore(store: backing)

        store.resetRoots()

        #expect(store.scanRoots.isEmpty)
        #expect(backing.stored.scanRoots.isEmpty)
        #expect(backing.saveCount == 1)
    }
}
