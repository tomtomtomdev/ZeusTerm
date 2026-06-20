import Testing
@testable import ZeusDomain

/// SPEC §7 / prototype zoom motion: `leave`, `enter`, and `idle` each have their OWN
/// transition. Critically the `enter` phase is `transition:none` — an INSTANT pre-scale set —
/// so the incoming level snaps to its SMALL (dive-in) / BIG (back) start and then unfolds
/// cleanly during the `idle` settle. Regression guard: applying a single shared animation to
/// every phase change animated the leave→enter scale jump, so dive-in expanded from the wrong
/// spot/scale instead of unfolding from the focal node.
struct StageMotionTests {

    @Test func enterPhaseIsInstantWithNoAnimation() {
        #expect(StageMotion.arriving(at: .enter) == nil)
    }

    @Test func leavePhaseUsesEaseInOver460ms() {
        #expect(StageMotion.arriving(at: .leave)
                == StageMotion(easing: StageMotion.Easing(0.6, 0, 0.78, 0), duration: 0.46))
    }

    @Test func idlePhaseSettlesWithEaseOutOver520ms() {
        #expect(StageMotion.arriving(at: .idle)
                == StageMotion(easing: StageMotion.Easing(0.16, 1, 0.3, 1), duration: 0.52))
    }
}
