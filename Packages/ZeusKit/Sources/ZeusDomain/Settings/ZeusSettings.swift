import Foundation

/// User-configurable app settings. Persisted by a `SettingsStoring` adapter.
public struct ZeusSettings: Codable, Sendable, Equatable {
    public var gradient: GradientConfig

    public init(gradient: GradientConfig = .aurora) {
        self.gradient = gradient
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

    public static let presets: [String: GradientConfig] = [
        "Aurora": .aurora,
        "Sunset": .sunset,
    ]
}
