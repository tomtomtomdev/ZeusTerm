import Foundation
import ZeusDomain

/// Pure layout + animation math for rendering a `GradientConfig` as a SwiftUI `MeshGradient`
/// (P7-E). Kept framework-free so it's unit-tested without a live view: `GradientBackground`
/// consumes it and maps `Point`→`SIMD2<Float>` / `colorsHex`→`Color` at render time.
///
/// A mesh needs a rectangular grid of control points with one color each. We size the grid to the
/// color count (2×2 for ≤4 colors, 3×3 for up to 9), space the points evenly across the unit
/// square corner-to-corner, and cycle the palette to fill every point.
struct MeshGradientPlan: Equatable {
    struct Point: Equatable { let x: Float; let y: Float }

    let columns: Int
    let rows: Int
    let points: [Point]
    let colorsHex: [String]

    private let animated: Bool
    private let animationSpeed: Double

    init(config: GradientConfig) {
        let side = Self.side(forColorCount: config.colorsHex.count)
        columns = side
        rows = side

        var pts: [Point] = []
        for row in 0..<rows {
            for col in 0..<columns {
                let x = columns == 1 ? 0 : Float(col) / Float(columns - 1)
                let y = rows == 1 ? 0 : Float(row) / Float(rows - 1)
                pts.append(Point(x: x, y: y))
            }
        }
        points = pts

        let palette = config.colorsHex.isEmpty ? ["#000000"] : config.colorsHex
        colorsHex = (0..<pts.count).map { palette[$0 % palette.count] }

        animated = config.animated
        animationSpeed = config.animationSpeed
    }

    /// Whether the mesh should animate — off when Reduce Motion is on (accessibility guardrail,
    /// SPEC §7) or the config disables animation.
    func isAnimating(reduceMotion: Bool) -> Bool { animated && !reduceMotion }

    /// One full drift cycle in seconds. Scales inversely with speed; a non-positive speed clamps to
    /// the base duration so we never divide by zero into a NaN/∞.
    var animationDuration: Double { Self.baseDuration / max(animationSpeed, 0.1) }

    private static let baseDuration: Double = 8

    /// Grid side length for a color count: at least 2 (a mesh needs a 2×2 minimum), at most 3.
    private static func side(forColorCount count: Int) -> Int {
        let ideal = Int(ceil(Double(count).squareRoot()))
        return min(max(ideal, 2), 3)
    }
}
