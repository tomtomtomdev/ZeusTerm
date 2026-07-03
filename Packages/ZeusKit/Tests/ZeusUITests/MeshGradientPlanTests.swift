import Testing
import ZeusDomain
@testable import ZeusUI

/// P7-E — the pure layout/animation math behind rendering a `GradientConfig` as an animated SwiftUI
/// `MeshGradient` (the view itself is proven with `/verify`; this pins the arithmetic).
///
/// Test List:
///  [x] a 4-color config lays out on a 2×2 grid (4 points)
///  [x] a 5–9 color config lays out on a 3×3 grid (9 points)
///  [x] the point grid spans the unit square corner-to-corner
///  [x] colors are cycled to fill every grid point
///  [x] animation is gated off by Reduce Motion and by the config's `animated` flag
///  [x] animation duration scales inversely with animationSpeed
struct MeshGradientPlanTests {

    @Test func fourColorsUseATwoByTwoGrid() {
        let plan = MeshGradientPlan(config: GradientConfig(style: .mesh,
                                                           colorsHex: ["#111111", "#222222", "#333333", "#444444"]))
        #expect(plan.columns == 2)
        #expect(plan.rows == 2)
        #expect(plan.points.count == 4)
    }

    @Test func manyColorsUseAThreeByThreeGrid() {
        let six = (0..<6).map { String(format: "#%06X", $0 * 0x111111) }
        let plan = MeshGradientPlan(config: GradientConfig(style: .mesh, colorsHex: six))
        #expect(plan.columns == 3)
        #expect(plan.rows == 3)
        #expect(plan.points.count == 9)
    }

    @Test func pointsSpanTheUnitSquare() {
        let plan = MeshGradientPlan(config: .aurora)   // 4 colors → 2×2
        #expect(plan.points.first == MeshGradientPlan.Point(x: 0, y: 0))
        #expect(plan.points.last == MeshGradientPlan.Point(x: 1, y: 1))
    }

    @Test func colorsAreCycledToFillEveryPoint() {
        // 2 colors on a 2×2 grid ⇒ 4 slots, cycled: A B A B.
        let plan = MeshGradientPlan(config: GradientConfig(style: .mesh, colorsHex: ["#AAAAAA", "#BBBBBB"]))
        #expect(plan.colorsHex.count == plan.points.count)
        #expect(plan.colorsHex == ["#AAAAAA", "#BBBBBB", "#AAAAAA", "#BBBBBB"])
    }

    @Test func reduceMotionAndTheAnimatedFlagGateAnimation() {
        let animated = GradientConfig(style: .mesh, colorsHex: ["#000000", "#FFFFFF"], animated: true)
        let still = GradientConfig(style: .mesh, colorsHex: ["#000000", "#FFFFFF"], animated: false)

        #expect(MeshGradientPlan(config: animated).isAnimating(reduceMotion: false) == true)
        #expect(MeshGradientPlan(config: animated).isAnimating(reduceMotion: true) == false)  // a11y guardrail
        #expect(MeshGradientPlan(config: still).isAnimating(reduceMotion: false) == false)
    }

    // P8-D perf: the nebula is a slow ~8s drift, so it's capped well below display refresh — 30fps is
    // visually identical to 120 but a quarter of the per-frame cos/sin cost, so it can't starve the
    // terminal (SPEC §6). The cap is expressed as a minimum seconds-per-frame the view feeds to
    // TimelineView(.animation(minimumInterval:)).
    @Test func meshAnimationIsCappedToAModestFrameRate() {
        let plan = MeshGradientPlan(config: .aurora)
        #expect(plan.frameInterval == 1.0 / 30.0)
    }

    @Test func durationScalesInverselyWithSpeed() {
        let fast = MeshGradientPlan(config: GradientConfig(style: .mesh, colorsHex: ["#000000", "#FFFFFF"], animationSpeed: 2))
        let slow = MeshGradientPlan(config: GradientConfig(style: .mesh, colorsHex: ["#000000", "#FFFFFF"], animationSpeed: 0.5))
        #expect(fast.animationDuration < slow.animationDuration)
        // A zero/negative speed must not divide-by-zero into a NaN/∞ duration.
        let zero = MeshGradientPlan(config: GradientConfig(style: .mesh, colorsHex: ["#000000"], animationSpeed: 0))
        #expect(zero.animationDuration.isFinite && zero.animationDuration > 0)
    }
}
