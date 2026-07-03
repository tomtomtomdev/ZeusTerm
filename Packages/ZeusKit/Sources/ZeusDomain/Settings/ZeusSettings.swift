import Foundation

/// The dark/light appearance preference (feature #7). Pure domain data — the SwiftUI `Theme`
/// token table in ZeusUI maps from it (shared raw values). Persisted in `ZeusSettings` so the
/// topbar sun/moon toggle survives relaunch.
public enum ThemeMode: String, Codable, Sendable, CaseIterable {
    case dark, light
}

/// User-configurable app settings. Persisted by a `SettingsStoring` adapter.
public struct ZeusSettings: Codable, Sendable, Equatable {
    public var gradient: GradientConfig

    /// User-configured discovery roots as filesystem path strings (feature #1, P3-D). Empty means
    /// "use the built-in dev roots" — `ScanRootResolver` applies that fallback. Stored as paths so
    /// the DTO stays Codable/Sendable without a `URL` dependency leaking into persistence.
    public var scanRoots: [String]

    /// The persisted dark/light preference (feature #7, P7-A).
    public var theme: ThemeMode

    public init(gradient: GradientConfig = .aurora, scanRoots: [String] = [], theme: ThemeMode = .dark) {
        self.gradient = gradient
        self.scanRoots = scanRoots
        self.theme = theme
    }

    // Custom decoding so settings persisted before a key existed still load: a missing `theme`
    // (pre-P7-A) falls back to `.dark` rather than failing the whole decode.
    private enum CodingKeys: String, CodingKey { case gradient, scanRoots, theme }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gradient = try container.decode(GradientConfig.self, forKey: .gradient)
        scanRoots = try container.decodeIfPresent([String].self, forKey: .scanRoots) ?? []
        theme = try container.decodeIfPresent(ThemeMode.self, forKey: .theme) ?? .dark
    }
}

/// Declarative description of the configurable gradient background (feature #7).
/// Lives in the domain as plain data; ZeusUI renders it.
public struct GradientConfig: Codable, Sendable, Equatable {
    public enum Style: String, Codable, Sendable, CaseIterable {
        case linear, radial, angular, mesh
    }

    public var style: Style
    /// Ordered color stops as `#RRGGBB` / `#RRGGBBAA` hex strings.
    public var colorsHex: [String]
    public var angleDegrees: Double
    public var animated: Bool
    public var animationSpeed: Double
    public var backgroundOpacity: Double

    public init(
        style: Style,
        colorsHex: [String],
        angleDegrees: Double = 45,
        animated: Bool = true,
        animationSpeed: Double = 1.0,
        backgroundOpacity: Double = 1.0
    ) {
        self.style = style
        self.colorsHex = colorsHex
        self.angleDegrees = angleDegrees
        self.animated = animated
        self.animationSpeed = animationSpeed
        self.backgroundOpacity = backgroundOpacity
    }

    public static let aurora = GradientConfig(
        style: .mesh,
        colorsHex: ["#0F2027", "#203A43", "#2C5364", "#1CB5E0"],
        angleDegrees: 45
    )

    public static let sunset = GradientConfig(
        style: .linear,
        colorsHex: ["#FF512F", "#DD2476"],
        angleDegrees: 30
    )

    /// Neutral grayscale — every stop is a pure gray (equal channels), for a distraction-free canvas.
    public static let mono = GradientConfig(
        style: .linear,
        colorsHex: ["#0A0A0A", "#2E2E2E", "#5A5A5A"],
        angleDegrees: 90
    )

    /// Green-on-black terminal aesthetic: black floor rising to bright phosphor green.
    public static let matrix = GradientConfig(
        style: .radial,
        colorsHex: ["#000000", "#003B00", "#00FF41"],
        angleDegrees: 0
    )

    /// A named preset in the Settings picker.
    public struct Preset: Sendable, Equatable {
        public let name: String
        public let config: GradientConfig
        public init(name: String, config: GradientConfig) {
            self.name = name
            self.config = config
        }
    }

    /// The preset catalog in display order (SPEC §2.7). Ordered (not a dict) so the picker is stable.
    public static let presets: [Preset] = [
        Preset(name: "Aurora", config: .aurora),
        Preset(name: "Sunset", config: .sunset),
        Preset(name: "Mono",   config: .mono),
        Preset(name: "Matrix", config: .matrix),
    ]

    /// Resolves a preset by name; nil for an unknown name.
    public static func preset(named name: String) -> GradientConfig? {
        presets.first { $0.name == name }?.config
    }
}
