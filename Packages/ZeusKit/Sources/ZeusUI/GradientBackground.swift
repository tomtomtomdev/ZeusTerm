import SwiftUI
import ZeusDomain

/// Renders the configurable gradient background (feature #7) from a `GradientConfig`.
/// P7 adds the animated `MeshGradient` (nebula) case; linear/radial/angular are static.
/// Layout/animation math lives in the pure, tested `MeshGradientPlan`.
public struct GradientBackground: View {
    public var config: GradientConfig
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        case .mesh:
            MeshNebula(plan: MeshGradientPlan(config: config), reduceMotion: reduceMotion)
        case .linear:
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        case .radial:
            RadialGradient(colors: colors, center: .center, startRadius: 0, endRadius: 600)
        case .angular:
            AngularGradient(colors: colors, center: .center, angle: .degrees(config.angleDegrees))
        }
    }
}

/// The animated mesh "nebula": a `MeshGradient` whose interior control points drift on a slow loop
/// (off under Reduce Motion). Corners stay pinned so the fill always covers the bleed.
private struct MeshNebula: View {
    let plan: MeshGradientPlan
    let reduceMotion: Bool

    var body: some View {
        if plan.isAnimating(reduceMotion: reduceMotion) {
            TimelineView(.animation) { timeline in
                let phase = timeline.date.timeIntervalSinceReferenceDate * (2 * .pi / plan.animationDuration)
                mesh(driftPhase: phase)
            }
        } else {
            mesh(driftPhase: nil)
        }
    }

    private func mesh(driftPhase: Double?) -> some View {
        MeshGradient(
            width: plan.columns,
            height: plan.rows,
            points: plan.points.enumerated().map { index, point in
                drifted(point, index: index, phase: driftPhase)
            },
            colors: plan.colorsHex.map(Color.init(hex:))
        )
    }

    /// Nudges interior points (never the pinned border) along a small circle keyed off their index,
    /// so the mesh breathes like a nebula. Border points return unchanged.
    private func drifted(_ p: MeshGradientPlan.Point, index: Int, phase: Double?) -> SIMD2<Float> {
        guard let phase, p.x > 0, p.x < 1, p.y > 0, p.y < 1 else {
            return SIMD2(p.x, p.y)
        }
        let amplitude: Float = 0.06
        let offset = Double(index) * 1.3
        let dx = Float(cos(phase + offset)) * amplitude
        let dy = Float(sin(phase + offset)) * amplitude
        return SIMD2(p.x + dx, p.y + dy)
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
