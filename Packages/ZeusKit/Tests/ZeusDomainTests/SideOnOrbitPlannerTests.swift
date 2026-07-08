import Testing
import Foundation
@testable import ZeusDomain

/// The worktree level is a **side-on solar system** (Design/HANDOFF §"Worktrees"): one orbit per
/// worktree, each ellipse flattened to `ry = rx·0.19`, the whole system tilted −13° about the sun,
/// and each planet's live size/opacity/z-order driven by its orbital depth so far-side planets duck
/// *behind* the sun. `SideOnOrbitPlanner` lays out the static geometry; `SideOnOrbits.state(of:at:)`
/// is the pure per-frame evaluator (the view feeds it a monotonic time). These are the exact
/// formulas transcribed from the prototype — assert them so the SwiftUI port can't drift.
struct SideOnOrbitPlannerTests {
    private let planner = SideOnOrbitPlanner()
    private let center = StagePoint(x: 512, y: 262)

    private func tenWorktrees() -> [WorktreeInput] {
        (0..<10).map { WorktreeInput(branch: "b\($0)", name: "api-\($0)", status: .clean) }
    }

    // MARK: - Static layout: one orbit per planet, stepping outward

    @Test func laysOutOneOrbitPerWorktree() {
        let orbits = planner.layout(center: center, name: "api", status: .dirty, worktrees: tenWorktrees())
        #expect(orbits.planets.count == 10)
        #expect(orbits.center.name == "api")
        #expect(orbits.center.status == .dirty)
    }

    @Test func orbitRadiiStepOutwardAndFlattenToNineteenPercent() {
        let orbits = planner.layout(center: center, name: "api", status: .clean, worktrees: tenWorktrees())
        for (i, planet) in orbits.planets.enumerated() {
            #expect(planet.rx == 145 + Double(i) * 52)          // 145 → 653
            #expect(abs(planet.ry - planet.rx * 0.19) < 1e-9)   // side-on flatten
        }
    }

    @Test func planetsPhaseByTheGoldenAngle() {
        let orbits = planner.layout(center: center, name: "api", status: .clean, worktrees: tenWorktrees())
        for (i, planet) in orbits.planets.enumerated() {
            #expect(abs(planet.phase - Double(i) * 2.3999) < 1e-9)
        }
    }

    @Test func innerPlanetsSweepFasterKeplerish() {
        let orbits = planner.layout(center: center, name: "api", status: .clean, worktrees: tenWorktrees())
        #expect(abs(orbits.planets[0].speed - 0.18) < 1e-9)     // rx/145 = 1 → base speed
        for i in 1..<orbits.planets.count {
            #expect(orbits.planets[i].speed < orbits.planets[i - 1].speed)
        }
    }

    @Test func systemIsTiltedThirteenDegrees() {
        let orbits = planner.layout(center: center, name: "api", status: .clean, worktrees: tenWorktrees())
        #expect(abs(orbits.tiltRadians - (-13.0 * .pi / 180)) < 1e-9)
    }

    // MARK: - Live per-frame state (the rotation + depth formulas)

    @Test func planetPositionRotatesByTheDiagonalTilt() {
        let orbits = planner.layout(center: center, name: "api", status: .clean,
                                    worktrees: [WorktreeInput(branch: "b0", name: "api-0", status: .clean)])
        // Planet 0: phase 0, so at t=0 θ=0 → dx=rx, dy=0, then rotated by −13° about the sun.
        let s = orbits.state(of: orbits.planets[0], at: 0)
        let rx = 145.0, ct = cos(-13.0 * .pi / 180), se = sin(-13.0 * .pi / 180)
        #expect(abs(s.point.x - (512 + rx * ct)) < 1e-6)
        #expect(abs(s.point.y - (262 + rx * se)) < 1e-6)
    }

    @Test func depthAtTheOrbitCrossingIsMidRange() {
        let orbits = planner.layout(center: center, name: "api", status: .clean,
                                    worktrees: [WorktreeInput(branch: "b0", name: "api-0", status: .clean)])
        let s = orbits.state(of: orbits.planets[0], at: 0)   // θ=0 → sin θ=0 → depth 0.5
        #expect(abs(s.depth - 0.5) < 1e-9)
        #expect(abs(s.size - 8.5 * (0.66 + 0.5 * 0.64)) < 1e-9)
        #expect(abs(s.opacity - 0.7) < 1e-9)
        #expect(s.zIndex == 105)
        #expect(s.labelOnRight == true)                       // cos θ ≥ 0
    }

    @Test func farSidePlanetDucksBehindTheSun() {
        // A planet phased to the far side (θ = −π/2 → sin θ = −1 → depth 0) must sort below the
        // sun's z-index (100); the near side (θ = +π/2 → depth 1) must sort above it.
        let far = OrbitPlanet(id: "far", branch: "f", name: "f", status: .clean,
                              rx: 145, baseSize: 8.5, phase: -.pi / 2, speed: 0.18)
        let near = OrbitPlanet(id: "near", branch: "n", name: "n", status: .clean,
                               rx: 145, baseSize: 8.5, phase: .pi / 2, speed: 0.18)
        let orbits = SideOnOrbits(center: OrbitCenter(point: center, name: "api", status: .clean),
                                  tiltRadians: -13.0 * .pi / 180, planets: [far, near])
        let farState = orbits.state(of: far, at: 0)
        let nearState = orbits.state(of: near, at: 0)
        #expect(abs(farState.depth - 0) < 1e-9)
        #expect(farState.zIndex < 100)                        // behind the sun
        #expect(abs(nearState.depth - 1) < 1e-9)
        #expect(nearState.zIndex > 100)                       // in front of the sun
        #expect(nearState.size > farState.size)               // near looms larger
    }

    @Test func noWorktreesLeaveAnEmptySystemWithJustTheSun() {
        let orbits = planner.layout(center: center, name: "api", status: .clean, worktrees: [])
        #expect(orbits.planets.isEmpty)
        #expect(orbits.center.name == "api")
    }
}
