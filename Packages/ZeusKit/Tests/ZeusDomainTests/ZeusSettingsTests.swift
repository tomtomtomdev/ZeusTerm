import Foundation
import Testing
@testable import ZeusDomain

/// `ZeusSettings` is the pure, Codable settings DTO a `SettingsStoring` adapter persists.
/// Slice 2A adds `scanRoots` (user-configured discovery roots, path strings).
///
/// Test List:
///  [x] scanRoots defaults to empty (so a fresh install falls back to the built-in dev roots)
///  [x] settings with scanRoots survive a Codable round-trip
struct ZeusSettingsTests {

    @Test func scanRootsDefaultsToEmpty() {
        #expect(ZeusSettings().scanRoots.isEmpty)
    }

    @Test func scanRootsSurviveACodableRoundTrip() throws {
        let original = ZeusSettings(scanRoots: ["/Users/me/Desktop", "/Users/me/work"])

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ZeusSettings.self, from: data)

        #expect(decoded == original)
        #expect(decoded.scanRoots == ["/Users/me/Desktop", "/Users/me/work"])
    }
}
