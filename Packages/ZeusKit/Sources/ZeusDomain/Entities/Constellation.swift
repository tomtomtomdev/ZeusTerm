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

/// A dashed elliptical orbit ring (the satellite track).
public struct OrbitRing: Sendable, Hashable {
    public var center: StagePoint
    public var rx: Double
    public var ry: Double
    public init(center: StagePoint, rx: Double, ry: Double) {
        self.center = center; self.rx = rx; self.ry = ry
    }
}

/// A worktree satellite orbiting the repo star, with its branch label placed radially outward.
public struct SatelliteNode: Identifiable, Sendable, Hashable {
    public let id: String
    public var branch: String
    public var name: String
    public var status: GitStatus
    public var point: StagePoint
    public var size: Double
    public var labelPoint: StagePoint
    public var labelOnRight: Bool

    public init(id: String, branch: String, name: String, status: GitStatus,
                point: StagePoint, size: Double, labelPoint: StagePoint, labelOnRight: Bool) {
        self.id = id; self.branch = branch; self.name = name; self.status = status
        self.point = point; self.size = size; self.labelPoint = labelPoint; self.labelOnRight = labelOnRight
    }
}

/// One orbit ring's configuration: radius, how many satellites, and a starting angle offset.
public struct RingSpec: Sendable, Hashable {
    public var radius: Double
    public var count: Int
    public var angleOffset: Double
    public init(radius: Double, count: Int, angleOffset: Double) {
        self.radius = radius; self.count = count; self.angleOffset = angleOffset
    }
}

public struct WorktreeInput: Sendable, Hashable {
    public var branch: String
    public var name: String
    public var status: GitStatus
    public init(branch: String, name: String, status: GitStatus) {
        self.branch = branch; self.name = name; self.status = status
    }
}

/// The laid-out worktree level: the repo star's orbit rings + satellites.
public struct ConstellationOrbits: Sendable, Hashable {
    public var center: StagePoint
    public var rings: [OrbitRing]
    public var satellites: [SatelliteNode]
    public init(center: StagePoint, rings: [OrbitRing], satellites: [SatelliteNode]) {
        self.center = center; self.rings = rings; self.satellites = satellites
    }

    /// Just the central repo star — no rings, no satellites. The neutral orbit shown while a repo
    /// loads or when its read fails, so the "empty orbit" shape lives in one place.
    public static func empty(center: StagePoint) -> ConstellationOrbits {
        ConstellationOrbits(center: center, rings: [], satellites: [])
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
