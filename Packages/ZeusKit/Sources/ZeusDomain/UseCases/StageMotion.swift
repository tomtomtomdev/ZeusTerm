import Foundation

/// Per-phase animation timing for the zoom stage (SPEC §7). Each phase has its OWN transition;
/// `arriving(at:)` returns the motion used when the stage *enters* a phase, or `nil` for an
/// **instant** set (no animation). The `enter` phase is instant on purpose — the incoming level
/// snaps pre-scaled to its SMALL (dive-in) / BIG (back) start while invisible, then unfolds
/// cleanly during the `idle` settle. The view maps `easing`+`duration` to a platform animation.
public struct StageMotion: Sendable, Equatable {

    /// Cubic-bézier easing control points — same parameterization as CSS `cubic-bezier(...)`.
    public struct Easing: Sendable, Equatable {
        public let c1x, c1y, c2x, c2y: Double
        public init(_ c1x: Double, _ c1y: Double, _ c2x: Double, _ c2y: Double) {
            self.c1x = c1x; self.c1y = c1y; self.c2x = c2x; self.c2y = c2y
        }
    }

    public let easing: Easing
    public let duration: Double

    public init(easing: Easing, duration: Double) {
        self.easing = easing
        self.duration = duration
    }

    /// The animation for arriving INTO `phase`; `nil` means snap instantly (no animation).
    public static func arriving(at phase: ZoomPhase) -> StageMotion? {
        switch phase {
        case .leave: return StageMotion(easing: Easing(0.6, 0, 0.78, 0), duration: 0.46)   // ease-in, fade out
        case .enter: return nil                                                            // transition:none — instant pre-scale
        case .idle:  return StageMotion(easing: Easing(0.16, 1, 0.3, 1), duration: 0.52)   // ease-out settle
        }
    }
}
