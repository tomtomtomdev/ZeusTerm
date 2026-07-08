import Foundation

/// Pure use case: lays out a repo's worktrees as a **side-on solar system** (Design/HANDOFF
/// §"Worktrees"). One orbit per worktree, stepping outward from the sun; each planet gets a
/// Kepler-ish angular speed (inner orbits sweep faster) and a golden-angle starting phase so they
/// don't clump. The static output feeds `SideOnOrbits.state(of:at:)`, which the view evaluates each
/// frame. Replaces the earlier flat nested-ring model (`OrbitRingPlanner` + `buildOrbits`).
public struct SideOnOrbitPlanner: Sendable {
    public init() {}

    /// Seat `worktrees` on their own orbits around the repo sun at `center`. `status` mirrors the
    /// repo's root (main worktree) so the sun is status-colored; nil while it loads.
    public func layout(center: StagePoint,
                       name: String,
                       status: GitStatus?,
                       worktrees: [WorktreeInput]) -> SideOnOrbits {
        let planets = worktrees.enumerated().map { index, worktree -> OrbitPlanet in
            let rx = SideOnOrbit.baseRadius + Double(index) * SideOnOrbit.radiusStep
            let speed = SideOnOrbit.baseSpeed / pow(rx / SideOnOrbit.baseRadius, SideOnOrbit.speedExponent)
            return OrbitPlanet(
                id: worktree.name,
                branch: worktree.branch,
                name: worktree.name,
                status: worktree.status,
                rx: rx,
                baseSize: SideOnOrbit.basePlanetSize,
                phase: Double(index) * SideOnOrbit.goldenAngle,
                speed: speed)
        }
        return SideOnOrbits(
            center: OrbitCenter(point: center, name: name, status: status),
            tiltRadians: SideOnOrbit.tiltRadians,
            planets: planets)
    }
}
