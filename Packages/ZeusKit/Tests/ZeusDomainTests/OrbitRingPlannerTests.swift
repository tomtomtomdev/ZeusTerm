import Testing
@testable import ZeusDomain

/// The orbit (worktree) level lays satellites on nested elliptical rings. With real git the
/// worktree count varies per repo, so `OrbitRingPlanner` sizes just enough rings to seat them —
/// reproducing the design prototype's nested-ellipse progression (radii 115/180/242, capacities
/// 3/4/3) so a real 10-worktree repo looks identical to the retiring sample fixture.
struct OrbitRingPlannerTests {
    private let planner = OrbitRingPlanner()

    @Test func aSingleWorktreeSitsEvenlyOnTheInnerRing() {
        #expect(planner.rings(forWorktreeCount: 1) == [RingSpec(radius: 115, count: 1, angleOffset: 0.4)])
    }

    @Test func noWorktreesProduceNoRings() {
        #expect(planner.rings(forWorktreeCount: 0) == [])
    }

    @Test func worktreesOverflowToTheNextRingPastTheInnerCapacity() {
        // Inner ring seats 3; the 4th spills to the second ring, which holds just that one.
        #expect(planner.rings(forWorktreeCount: 4) == [
            RingSpec(radius: 115, count: 3, angleOffset: 0.4),
            RingSpec(radius: 180, count: 1, angleOffset: 0.85),
        ])
    }

    @Test func tenWorktreesReproduceTheDesignPrototypeRings() {
        // The exact rings `SampleConstellationData` hard-codes — so the fixture can retire without
        // shifting any satellite once the real worktree level is wired in.
        #expect(planner.rings(forWorktreeCount: 10) == [
            RingSpec(radius: 115, count: 3, angleOffset: 0.4),
            RingSpec(radius: 180, count: 4, angleOffset: 0.85),
            RingSpec(radius: 242, count: 3, angleOffset: 0.15),
        ])
    }

    @Test func beyondTheTemplateRingsGrowOutwardSoNoSatelliteIsDropped() {
        // 12 worktrees: the three template rings (cap 10) plus a fourth, 62pt further out.
        #expect(planner.rings(forWorktreeCount: 12) == [
            RingSpec(radius: 115, count: 3, angleOffset: 0.4),
            RingSpec(radius: 180, count: 4, angleOffset: 0.85),
            RingSpec(radius: 242, count: 3, angleOffset: 0.15),
            RingSpec(radius: 304, count: 2, angleOffset: 0.4),
        ])
    }
}
