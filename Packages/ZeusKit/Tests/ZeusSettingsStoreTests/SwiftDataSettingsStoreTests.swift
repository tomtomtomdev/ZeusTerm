import Foundation
import Testing
import ZeusDomain
@testable import ZeusSettingsStore

/// P3-D (roots, Slice 2B) — the SwiftData adapter that persists `ZeusSettings` behind the
/// domain's `SettingsStoring` port. SwiftData stays here in infrastructure; the domain only
/// ever sees the pure `ZeusSettings` struct (no `@Model` leaks inward).
///
/// Tests run against an in-memory `ModelContainer` so they're fast and leave no files behind.
///
/// Test List:
///  [x] fresh store (nothing saved) → load() returns default ZeusSettings
///  [x] save then load round-trips the settings (incl. scanRoots + gradient)
///  [x] saving twice keeps a single record — the second load reflects the latest
struct SwiftDataSettingsStoreTests {

    private func makeStore() throws -> SwiftDataSettingsStore {
        try SwiftDataSettingsStore(inMemory: true)
    }

    @Test func loadOnFreshStoreReturnsDefaults() throws {
        let store = try makeStore()

        #expect(try store.load() == ZeusSettings())
    }

    @Test func savedSettingsRoundTrip() throws {
        let store = try makeStore()
        let settings = ZeusSettings(gradient: .sunset, scanRoots: ["/Users/me/Desktop", "/Users/me/work"])

        try store.save(settings)

        #expect(try store.load() == settings)
    }

    @Test func saveReplacesPreviousSettingsKeepingASingleRecord() throws {
        let store = try makeStore()

        try store.save(ZeusSettings(scanRoots: ["/a"]))
        try store.save(ZeusSettings(scanRoots: ["/b", "/c"]))

        #expect(try store.load().scanRoots == ["/b", "/c"])
    }
}
