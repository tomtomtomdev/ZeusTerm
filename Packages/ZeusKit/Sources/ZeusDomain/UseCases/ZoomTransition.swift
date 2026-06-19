import Foundation

/// Which phase of a level transition the stage is in (SPEC §7 zoom motion).
public enum ZoomPhase: Sendable, Hashable { case idle, leave, enter }

/// Whether the camera is diving into a node (`inward`) or backing out (`outward`).
public enum ZoomDirection: Sendable, Hashable { case inward, outward }

/// Pure zoom math: the animatable stage transform for a given phase/direction.
/// One stage is scaled about a **focal node**; `BIG = zoomDepth`, `SMALL = (1/BIG)·1.15`
/// are reciprocals, so the scale step between nested levels reads as constant. The view
/// supplies the easing/duration per phase; this type only yields scale/anchor/opacity.
public struct ZoomTransition: Sendable, Hashable {
    public let scale: Double
    public let anchor: StagePoint   // stage coords; the view maps to a UnitPoint
    public let opacity: Double

    public static func make(phase: ZoomPhase,
                            dir: ZoomDirection,
                            leaveOrigin: StagePoint,
                            enterOrigin: StagePoint,
                            zoomDepth: Double = 7,
                            reduceMotion: Bool = false) -> ZoomTransition {
        guard !reduceMotion else {
            return ZoomTransition(scale: 1, anchor: enterOrigin, opacity: 1)
        }
        let big = zoomDepth
        let small = (1 / big) * 1.15
        switch phase {
        case .leave:
            // Diving in: parent flies INTO the node (→BIG). Backing out: child collapses (→SMALL).
            return ZoomTransition(scale: dir == .inward ? big : small, anchor: leaveOrigin, opacity: 0)
        case .enter:
            // Diving in: child unfolds FROM the node (SMALL→). Backing out: parent pulls back (BIG→).
            return ZoomTransition(scale: dir == .inward ? small : big, anchor: enterOrigin, opacity: 0)
        case .idle:
            return ZoomTransition(scale: 1, anchor: enterOrigin, opacity: 1)
        }
    }
}
