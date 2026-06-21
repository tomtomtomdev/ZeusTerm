import Foundation

/// Pure use case: sizes the orbit (worktree) level's nested elliptical rings to seat a given
/// number of worktree satellites. Real repos have a variable worktree count, so this returns just
/// enough rings — innermost first — following the design prototype's progression. Feeds
/// `ConstellationLayout.buildOrbits(center:worktrees:rings:)`.
public struct OrbitRingPlanner: Sendable {
    /// The prototype's nested ellipses: radius, seat capacity, and starting angle. Worktrees fill
    /// these innermost-first; ten worktrees exactly fill all three (matching the sample fixture).
    private static let template: [(radius: Double, capacity: Int, angleOffset: Double)] = [
        (115, 3, 0.4), (180, 4, 0.85), (242, 3, 0.15),
    ]
    /// Past the template, rings keep stepping outward by this gap (the 180→242 spacing) so a repo
    /// with an unusually large number of worktrees never drops a satellite.
    private static let overflowGap: Double = 62
    private static let overflowCapacity = 4

    public init() {}

    /// Just enough rings — innermost first — to seat `count` satellites, each ring's `count` set to
    /// how many actually land on it so `buildOrbits` distributes them evenly around that ring.
    public func rings(forWorktreeCount count: Int) -> [RingSpec] {
        var rings: [RingSpec] = []
        var remaining = count
        var index = 0
        while remaining > 0 {
            let (radius, capacity, angleOffset) = ringTemplate(at: index)
            let seated = min(remaining, capacity)
            rings.append(RingSpec(radius: radius, count: seated, angleOffset: angleOffset))
            remaining -= seated
            index += 1
        }
        return rings
    }

    /// The ring at `index`: a fixed template ring, or an extrapolated one stepping outward past it,
    /// cycling the template's angle offsets so successive rings stay visually staggered.
    private func ringTemplate(at index: Int) -> (radius: Double, capacity: Int, angleOffset: Double) {
        if index < Self.template.count { return Self.template[index] }
        let stepsOut = index - Self.template.count + 1
        let radius = Self.template[Self.template.count - 1].radius + Self.overflowGap * Double(stepsOut)
        let angleOffset = Self.template[index % Self.template.count].angleOffset
        return (radius, Self.overflowCapacity, angleOffset)
    }
}
