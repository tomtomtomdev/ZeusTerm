import Foundation
import Testing
@testable import ZeusDomain

/// `GradientConfig` is the pure, Codable description of the configurable background (feature #7).
/// P7-B rounds out the preset catalog (SPEC §2.7: "Aurora", "Sunset", "Mono", "Matrix") behind an
/// *ordered* list so the Settings preset picker renders deterministically, plus a name lookup.
///
/// Test List:
///  [x] the preset catalog lists Aurora, Sunset, Mono, Matrix in display order
///  [x] preset(named:) resolves each catalog entry and is nil for an unknown name
///  [x] Mono is a neutral grayscale gradient
///  [x] Matrix is a green-on-black gradient
struct GradientConfigTests {

    @Test func presetCatalogIsOrderedForDisplay() {
        #expect(GradientConfig.presets.map(\.name) == ["Aurora", "Sunset", "Mono", "Matrix"])
    }

    @Test func presetNamedResolvesEachCatalogEntry() {
        for preset in GradientConfig.presets {
            #expect(GradientConfig.preset(named: preset.name) == preset.config)
        }
        #expect(GradientConfig.preset(named: "Nope") == nil)
    }

    @Test func monoIsAGrayscaleGradient() {
        let mono = GradientConfig.mono
        // Every channel equal in every stop ⇒ neutral gray (no hue).
        for hex in mono.colorsHex {
            let (r, g, b) = Self.rgb(hex)
            #expect(r == g && g == b)
        }
    }

    @Test func matrixIsGreenOnBlack() {
        let matrix = GradientConfig.matrix
        let (r0, g0, b0) = Self.rgb(matrix.colorsHex.first!)
        let (_, gN, _) = Self.rgb(matrix.colorsHex.last!)
        #expect(r0 == 0 && g0 == 0 && b0 == 0)   // starts at black
        #expect(gN > 200)                          // ends bright green
    }

    /// Parses `#RRGGBB` into 0–255 channels (test-local; the app parses hex in ZeusUI).
    private static func rgb(_ hex: String) -> (Int, Int, Int) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        return (Int((v >> 16) & 0xFF), Int((v >> 8) & 0xFF), Int(v & 0xFF))
    }
}
