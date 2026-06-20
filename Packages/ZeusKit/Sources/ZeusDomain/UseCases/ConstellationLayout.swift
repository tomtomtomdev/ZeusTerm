import Foundation

/// Pure use case: lays out the constellation levels in stage space (SPEC §7).
/// Deterministic — a seeded PRNG ([[SeededGenerator]]) jitters cluster members so the
/// map is stable across runs while keeping the design's organic character. No UI here.
public struct ConstellationLayout: Sendable {
    /// Seed matching the design prototype (`mulberry32(1337)`).
    private let seed: UInt32

    public init(seed: UInt32 = 1337) { self.seed = seed }

    /// Hub level: a central hub star + each cluster's members on a jittered ring around
    /// its center, connected in sequence with the first member tied (faintly) to the hub.
    public func buildHub(clusters: [ClusterInput], hub: HubInput) -> ConstellationHub {
        var rng = SeededGenerator(seed: seed)
        var stars = [StarNode(id: hub.name, name: hub.name, point: hub.center,
                              size: 16, status: nil, isHub: true)]
        var edges: [StageEdge] = []
        var labels: [ClusterLabel] = []

        for (clusterIndex, cluster) in clusters.enumerated() {
            labels.append(ClusterLabel(
                text: cluster.type,
                point: StagePoint(x: cluster.center.x, y: cluster.center.y - cluster.spread - 12)))

            var members: [StarNode] = []
            let count = cluster.members.count
            for (i, member) in cluster.members.enumerated() {
                // Two PRNG draws per member (angle jitter, then radius) — order is load-bearing
                // for determinism, mirroring the reference layout.
                let angle = (Double(i) / Double(count)) * 2 * .pi
                    + (rng.next() - 0.5) * 0.9
                    + Double(clusterIndex) * 1.7
                let radius = cluster.spread * (0.42 + rng.next() * 0.6)
                let point = StagePoint(
                    x: cluster.center.x + cos(angle) * radius,
                    y: cluster.center.y + sin(angle) * radius * 0.82)   // flatter look
                let size = 6 + (i % 2 == 1 ? 2.5 : 0) + (i == 0 ? 3 : 0)
                let star = StarNode(id: member.id, name: member.name, point: point,
                                    size: size, status: member.status, isHub: false)
                members.append(star)
                stars.append(star)
            }

            for i in members.indices.dropLast() {
                edges.append(StageEdge(from: members[i].point, to: members[i + 1].point, dim: false))
            }
            if let first = members.first {
                edges.append(StageEdge(from: first.point, to: hub.center, dim: true))
            }
        }
        return ConstellationHub(stars: stars, edges: edges, labels: labels)
    }

    /// Worktree level: the repo star centered, worktrees distributed across elliptical
    /// orbit rings (filled in order). `squash` flattens the rings (ry = rx·squash).
    public func buildOrbits(center: StagePoint,
                            worktrees: [WorktreeInput],
                            rings: [RingSpec],
                            squash: Double = 0.72) -> ConstellationOrbits {
        var orbitRings: [OrbitRing] = []
        var satellites: [SatelliteNode] = []
        var next = 0

        for ring in rings {
            orbitRings.append(OrbitRing(center: center, rx: ring.radius, ry: ring.radius * squash))
            for i in 0..<ring.count where next < worktrees.count {
                let worktree = worktrees[next]
                next += 1
                let angle = ring.angleOffset + (Double(i) / Double(ring.count)) * 2 * .pi
                let point = StagePoint(
                    x: center.x + cos(angle) * ring.radius,
                    y: center.y + sin(angle) * ring.radius * squash)
                // Label sits 16pt radially outward along the (squashed) normal direction.
                let nx = cos(angle), ny = sin(angle) * squash
                let length = (nx * nx + ny * ny).squareRoot()
                let unit = length == 0 ? 1 : length
                let labelPoint = StagePoint(x: point.x + nx / unit * 16, y: point.y + ny / unit * 16)
                satellites.append(SatelliteNode(
                    id: worktree.name, branch: worktree.branch, name: worktree.name,
                    status: worktree.status, point: point, size: 9.5,
                    labelPoint: labelPoint, labelOnRight: nx >= 0))
            }
        }
        return ConstellationOrbits(center: center, rings: orbitRings, satellites: satellites)
    }
}
