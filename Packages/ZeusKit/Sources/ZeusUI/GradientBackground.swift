import SwiftUI
import ZeusDomain

/// Renders the configurable gradient background (feature #7) from a `GradientConfig`.
/// P0 covers linear/radial/angular; animated `MeshGradient` lands in P7 (SPEC §2.7).
public struct GradientBackground: View {
    public var config: GradientConfig

    public init(config: GradientConfig) {
        self.config = config
    }

    public var body: some View {
        gradient
            .opacity(config.backgroundOpacity)
            .ignoresSafeArea()
    }

    @ViewBuilder private var gradient: some View {
        let colors = config.colorsHex.map(Color.init(hex:))
        switch config.style {
        case .linear, .mesh: // mesh falls back to linear until P7
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        case .radial:
            RadialGradient(colors: colors, center: .center, startRadius: 0, endRadius: 600)
        case .angular:
            AngularGradient(colors: colors, center: .center, angle: .degrees(config.angleDegrees))
        }
    }
}

extension Color {
    /// Initializes from a `#RRGGBB` or `#RRGGBBAA` hex string.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r, g, b, a: Double
        if cleaned.count == 8 {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        } else {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
