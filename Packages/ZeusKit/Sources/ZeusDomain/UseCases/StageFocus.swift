import Foundation

/// A node the keyboard can focus: a stable `id` plus its center in stage space. Every constellation
/// level maps its own nodes (hub stars, orbit satellites, commit dots) down to this, so directional
/// navigation is one tested policy rather than three (SPEC §7 keyboard accessibility).
public struct FocusNode: Sendable, Hashable {
    public let id: String
    public let point: StagePoint
    public init(id: String, point: StagePoint) {
        self.id = id
        self.point = point
    }
}

/// The four arrow-key directions. Stage coords grow y downward, so `.up` seeks a smaller y.
public enum FocusDirection: Sendable, Hashable { case up, down, left, right }

/// Pure directional focus navigation over stage nodes. `next` returns the id to focus after an arrow
/// press (or `nil` to stay put when there's nothing that way); `initialFocus` picks the entry node.
public enum StageFocus {

    /// The node to focus after pressing `direction` from `current`.
    /// - `nil` current seeds the entry node (a stray arrow before focus is set).
    /// - Returns `nil` when no node lies in that direction — the caller keeps the current focus.
    public static func next(from current: String?, direction: FocusDirection,
                            in nodes: [FocusNode]) -> String? {
        guard let current, let origin = nodes.first(where: { $0.id == current }) else {
            return initialFocus(in: nodes)
        }

        let candidates = nodes.filter { $0.id != current && inDirection(direction, from: origin.point, to: $0.point) }
        return candidates.min { lhs, rhs in
            let a = cost(direction, from: origin.point, to: lhs.point)
            let b = cost(direction, from: origin.point, to: rhs.point)
            if a.total != b.total { return a.total < b.total }
            if a.perp != b.perp { return a.perp < b.perp }
            if a.along != b.along { return a.along < b.along }
            return lhs.id < rhs.id   // stable, deterministic final tie-break
        }?.id
    }

    /// The node to focus when a level appears: `preferred` when it exists (e.g. the tree seeds HEAD),
    /// else the topmost-leftmost node, else `nil` for an empty map.
    public static func initialFocus(in nodes: [FocusNode], preferred: String? = nil) -> String? {
        if let preferred, nodes.contains(where: { $0.id == preferred }) { return preferred }
        return nodes.min { lhs, rhs in
            if lhs.point.y != rhs.point.y { return lhs.point.y < rhs.point.y }
            if lhs.point.x != rhs.point.x { return lhs.point.x < rhs.point.x }
            return lhs.id < rhs.id
        }?.id
    }

    /// Whether `to` sits in `direction`'s half-plane relative to `from`.
    private static func inDirection(_ direction: FocusDirection, from: StagePoint, to: StagePoint) -> Bool {
        switch direction {
        case .up:    return to.y < from.y
        case .down:  return to.y > from.y
        case .left:  return to.x < from.x
        case .right: return to.x > from.x
        }
    }

    /// Distance split into travel *along* the pressed axis and *perpendicular* drift. Perpendicular
    /// drift is weighted so an axis-aligned neighbor beats a nearer diagonal one.
    private static func cost(_ direction: FocusDirection, from: StagePoint, to: StagePoint)
        -> (total: Double, along: Double, perp: Double) {
        let dx = abs(to.x - from.x), dy = abs(to.y - from.y)
        let (along, perp): (Double, Double)
        switch direction {
        case .up, .down:    (along, perp) = (dy, dx)
        case .left, .right: (along, perp) = (dx, dy)
        }
        return (along + perp * 2, along, perp)
    }
}
