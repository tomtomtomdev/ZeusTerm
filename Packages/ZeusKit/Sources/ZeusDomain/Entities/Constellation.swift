import Foundation

// Value types for the constellation UI (SPEC §7). All coordinates are in the 1040×540
// "stage" space; the presentation layer maps them to SwiftUI positions/transforms.

/// A point in stage space (origin top-left, matching CSS / SwiftUI layout coords).
public struct StagePoint: Sendable, Hashable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// A star on the hub map: a repo (status-colored) or the central monorepo hub.
public struct StarNode: Identifiable, Sendable, Hashable {
    public let id: String
    public var name: String
    public var point: StagePoint
    public var size: Double
    public var status: GitStatus?   // nil for the hub
    public var isHub: Bool

    public init(id: String, name: String, point: StagePoint, size: Double,
                status: GitStatus?, isHub: Bool) {
        self.id = id; self.name = name; self.point = point
        self.size = size; self.status = status; self.isHub = isHub
    }
}

/// A constellation line between two stage points. `dim` marks the fainter cluster→hub link.
public struct StageEdge: Sendable, Hashable {
    public var from: StagePoint
    public var to: StagePoint
    public var dim: Bool
    public init(from: StagePoint, to: StagePoint, dim: Bool) {
        self.from = from; self.to = to; self.dim = dim
    }
}

/// A floating cluster-type label (e.g. "Backend") positioned above its cluster.
public struct ClusterLabel: Sendable, Hashable {
    public var text: String
    public var point: StagePoint
    public init(text: String, point: StagePoint) { self.text = text; self.point = point }
}

// MARK: - Hub inputs / output

public struct MemberInput: Sendable, Hashable {
    /// Stable identity (the repo's filesystem path for real scans) — distinct from the
    /// display `name`, so two repos sharing a folder name don't collide as one star.
    public var id: String
    public var name: String
    public var status: GitStatus
    /// `id` defaults to `name` for fixtures/tests where display names are already unique.
    public init(id: String? = nil, name: String, status: GitStatus) {
        self.id = id ?? name; self.name = name; self.status = status
    }
}

public struct ClusterInput: Sendable, Hashable {
    public var type: String
    public var center: StagePoint
    public var spread: Double
    public var members: [MemberInput]
    public init(type: String, center: StagePoint, spread: Double, members: [MemberInput]) {
        self.type = type; self.center = center; self.spread = spread; self.members = members
    }
}

public struct HubInput: Sendable, Hashable {
    public var name: String
    public var center: StagePoint
    public init(name: String, center: StagePoint) { self.name = name; self.center = center }
}

/// The laid-out hub level: stars (hub + cluster members), constellation lines, cluster labels.
public struct ConstellationHub: Sendable, Hashable {
    public var stars: [StarNode]
    public var edges: [StageEdge]
    public var labels: [ClusterLabel]
    public init(stars: [StarNode], edges: [StageEdge], labels: [ClusterLabel]) {
        self.stars = stars; self.edges = edges; self.labels = labels
    }
}

// MARK: - Worktree orbit level

public struct WorktreeInput: Sendable, Hashable {
    public var branch: String
    public var name: String
    public var status: GitStatus
    public init(branch: String, name: String, status: GitStatus) {
        self.branch = branch; self.name = name; self.status = status
    }
}

/// The central repo star at the orbit level: where it sits, plus what it represents — the
/// dived-into repo's name and a status mirroring its root (the main worktree). Distinct from a bare
/// `StagePoint` so the center renders a label + status color instead of an anonymous dot. `status`
/// is nil while the repo loads / has no worktrees.
public struct OrbitCenter: Sendable, Hashable {
    public var point: StagePoint
    public var name: String
    public var status: GitStatus?
    public init(point: StagePoint, name: String, status: GitStatus?) {
        self.point = point; self.name = name; self.status = status
    }
}

// MARK: - Worktree orbit level (side-on solar system)

/// Fixed geometry/motion constants for the side-on worktree system (Design/HANDOFF §"Worktrees").
/// One orbit per worktree; ellipses flattened to `ry = rx·flatten`; the whole system tilted about
/// the sun; planet speed falls off with radius (Kepler-ish); phases spread by the golden angle.
public enum SideOnOrbit {
    public static let flatten = 0.19            // ry = rx · 0.19 → near edge-on
    public static let tiltDegrees = -13.0       // whole system rotated diagonally about the sun
    public static let baseRadius = 145.0        // innermost orbit rx
    public static let radiusStep = 52.0         // rx = baseRadius + i·radiusStep
    public static let baseSpeed = 0.18          // angular speed at the innermost orbit
    public static let speedExponent = 1.35      // speed = baseSpeed / (rx/baseRadius)^exponent
    public static let goldenAngle = 2.3999      // starting-phase spread so planets don't clump
    public static let basePlanetSize = 8.5      // planet disc size before the depth scale

    public static var tiltRadians: Double { tiltDegrees * .pi / 180 }
}

/// One worktree planet: its orbit (`rx`, derived `ry`) plus the motion params that place it each
/// frame. Static — the live position/size/z comes from `SideOnOrbits.state(of:at:)`.
public struct OrbitPlanet: Identifiable, Sendable, Hashable {
    public let id: String
    public var branch: String
    public var name: String
    public var status: GitStatus
    public var rx: Double
    public var baseSize: Double
    public var phase: Double      // θ₀ — starting angle
    public var speed: Double      // radians per unit time

    /// The flattened semi-minor axis — what makes the orbit read side-on.
    public var ry: Double { rx * SideOnOrbit.flatten }

    public init(id: String, branch: String, name: String, status: GitStatus,
                rx: Double, baseSize: Double, phase: Double, speed: Double) {
        self.id = id; self.branch = branch; self.name = name; self.status = status
        self.rx = rx; self.baseSize = baseSize; self.phase = phase; self.speed = speed
    }
}

/// A planet's evaluated frame: where it is, how big/bright, and its z-order relative to the sun
/// (which sits at z 100 — planets with `zIndex < 100` render *behind* it).
public struct PlanetState: Sendable, Hashable {
    public var point: StagePoint
    public var depth: Double       // 0 = far side (behind sun) … 1 = near side (in front)
    public var size: Double
    public var opacity: Double
    public var zIndex: Int
    public var labelOnRight: Bool
    public init(point: StagePoint, depth: Double, size: Double, opacity: Double,
                zIndex: Int, labelOnRight: Bool) {
        self.point = point; self.depth = depth; self.size = size
        self.opacity = opacity; self.zIndex = zIndex; self.labelOnRight = labelOnRight
    }
}

/// The laid-out side-on worktree level: the repo sun, the tilt applied to the whole system, and its
/// orbiting planets. `state(of:at:)` is the pure per-frame evaluator the view drives with a clock.
public struct SideOnOrbits: Sendable, Hashable {
    public var center: OrbitCenter
    public var tiltRadians: Double
    public var planets: [OrbitPlanet]
    public init(center: OrbitCenter, tiltRadians: Double, planets: [OrbitPlanet]) {
        self.center = center; self.tiltRadians = tiltRadians; self.planets = planets
    }

    /// The neutral system shown while a repo loads or its read fails: just the sun, no planets.
    public static func empty(center: StagePoint, name: String = "") -> SideOnOrbits {
        SideOnOrbits(center: OrbitCenter(point: center, name: name, status: nil),
                     tiltRadians: SideOnOrbit.tiltRadians, planets: [])
    }

    /// Evaluate `planet` at time `t`: orbit point (rotated by the system tilt), plus the depth-driven
    /// size/opacity/z-order that make planets pass in front of and behind the sun. Pure — same `t`
    /// yields the same frame, so it's unit-testable and reduce-motion just pins `t` to 0.
    public func state(of planet: OrbitPlanet, at t: Double) -> PlanetState {
        let theta = planet.phase + t * planet.speed
        let dx = planet.rx * cos(theta)
        let dy = planet.ry * sin(theta)
        let ct = cos(tiltRadians), se = sin(tiltRadians)
        let x = center.point.x + dx * ct - dy * se
        let y = center.point.y + dx * se + dy * ct
        let depth = (sin(theta) + 1) / 2
        return PlanetState(
            point: StagePoint(x: x, y: y),
            depth: depth,
            size: planet.baseSize * (0.66 + depth * 0.64),
            opacity: 0.4 + depth * 0.6,
            zIndex: Int((60 + depth * 90).rounded()),
            labelOnRight: cos(theta) >= 0)
    }
}

// MARK: - Branch-tree (commit graph) level

/// A commit ready for graph layout: its sha, message, lane branch, and parent shas.
public struct GraphCommit: Sendable, Hashable {
    public var sha: String
    public var summary: String
    public var branch: String
    public var parents: [String]
    public init(sha: String, summary: String, branch: String, parents: [String]) {
        self.sha = sha; self.summary = summary; self.branch = branch; self.parents = parents
    }
}

/// A laid-out commit node. `rank` is the topological order (newest = highest = top).
public struct CommitNode: Identifiable, Sendable, Hashable {
    public let id: String   // sha
    public var branch: String
    public var summary: String
    public var point: StagePoint
    public var rank: Int
    public var isHead: Bool
    public var isDim: Bool   // newer than HEAD (rank > HEAD's rank)

    public init(id: String, branch: String, summary: String, point: StagePoint,
                rank: Int, isHead: Bool, isDim: Bool) {
        self.id = id; self.branch = branch; self.summary = summary
        self.point = point; self.rank = rank; self.isHead = isHead; self.isDim = isDim
    }
}

/// A 2px graph edge from a commit to a present parent, colored by the child's branch.
public struct CommitEdge: Sendable, Hashable {
    public var from: StagePoint
    public var to: StagePoint
    public var branch: String
    public init(from: StagePoint, to: StagePoint, branch: String) {
        self.from = from; self.to = to; self.branch = branch
    }
}

/// The laid-out branch-tree level.
public struct ConstellationTree: Sendable, Hashable {
    public var nodes: [CommitNode]
    public var edges: [CommitEdge]
    public init(nodes: [CommitNode], edges: [CommitEdge]) {
        self.nodes = nodes; self.edges = edges
    }
}
