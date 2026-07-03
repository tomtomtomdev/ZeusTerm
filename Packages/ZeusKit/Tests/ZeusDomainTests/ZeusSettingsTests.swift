import Foundation
import Testing
@testable import ZeusDomain

/// `ZeusSettings` is the pure, Codable settings DTO a `SettingsStoring` adapter persists.
/// Slice 2A adds `scanRoots` (user-configured discovery roots, path strings).
/// P7-A adds `theme` (the persisted dark/light preference behind the topbar sun/moon toggle).
///
/// Test List:
///  [x] scanRoots defaults to empty (so a fresh install falls back to the built-in dev roots)
///  [x] settings with scanRoots survive a Codable round-trip
///  [x] theme defaults to .dark
///  [x] theme survives a Codable round-trip
///  [x] legacy settings JSON without a `theme` key decodes to .dark (backward compatible)
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

    @Test func themeDefaultsToDark() {
        #expect(ZeusSettings().theme == .dark)
    }

    @Test func themeSurvivesACodableRoundTrip() throws {
        let original = ZeusSettings(theme: .light)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ZeusSettings.self, from: data)

        #expect(decoded == original)
        #expect(decoded.theme == .light)
    }

    /// Settings persisted before P7-A have no `theme` key; decoding must not fail and must fall
    /// back to `.dark` so an existing install keeps a valid theme after upgrade.
    @Test func legacySettingsWithoutAThemeKeyDecodeToDark() throws {
        let legacyJSON = """
        { "gradient": \(String(data: try JSONEncoder().encode(GradientConfig.aurora), encoding: .utf8)!),
          "scanRoots": ["/a"] }
        """

        let decoded = try JSONDecoder().decode(ZeusSettings.self, from: Data(legacyJSON.utf8))

        #expect(decoded.theme == .dark)
        #expect(decoded.scanRoots == ["/a"])
    }
}
