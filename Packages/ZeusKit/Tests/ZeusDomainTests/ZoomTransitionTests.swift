import Testing
import Foundation
@testable import ZeusDomain

struct ZoomTransitionTests {
    private let origin = StagePoint(x: 100, y: 50)

    private func small(_ big: Double) -> Double { (1 / big) * 1.15 }

    @Test func diveInFliesIntoTheFocalNode() {
        // leave: parent scales 1→BIG and fades out, pivoting on the focal (leave) origin
        let leave = ZoomTransition.make(phase: .leave, dir: .inward,
                                        leaveOrigin: origin, enterOrigin: origin, zoomDepth: 7)
        #expect(leave.scale == 7)
        #expect(leave.opacity == 0)
        #expect(leave.anchor == origin)

        // enter: child mounts pre-scaled at SMALL, then unfolds
        let enter = ZoomTransition.make(phase: .enter, dir: .inward,
                                        leaveOrigin: origin, enterOrigin: origin, zoomDepth: 7)
        #expect(abs(enter.scale - small(7)) < 1e-12)
        #expect(enter.opacity == 0)
    }

    @Test func backOutReversesTheZoom() {
        let leave = ZoomTransition.make(phase: .leave, dir: .outward,
                                        leaveOrigin: origin, enterOrigin: origin, zoomDepth: 7)
        #expect(abs(leave.scale - small(7)) < 1e-12)   // child collapses into the node
        let enter = ZoomTransition.make(phase: .enter, dir: .outward,
                                        leaveOrigin: origin, enterOrigin: origin, zoomDepth: 7)
        #expect(enter.scale == 7)                        // parent pulls back out
    }

    @Test func idleSettlesToIdentityAtEnterOrigin() {
        let enterOrigin = StagePoint(x: 300, y: 200)
        let t = ZoomTransition.make(phase: .idle, dir: .inward,
                                    leaveOrigin: origin, enterOrigin: enterOrigin, zoomDepth: 7)
        #expect(t.scale == 1)
        #expect(t.opacity == 1)
        #expect(t.anchor == enterOrigin)
    }

    @Test func reduceMotionIsAlwaysIdentity() {
        let t = ZoomTransition.make(phase: .leave, dir: .inward,
                                    leaveOrigin: origin, enterOrigin: origin,
                                    zoomDepth: 7, reduceMotion: true)
        #expect(t.scale == 1 && t.opacity == 1)
    }

    @Test func bigAndSmallAreReciprocalSoTheScaleStepReadsConstant() {
        let enter = ZoomTransition.make(phase: .enter, dir: .inward,
                                        leaveOrigin: origin, enterOrigin: origin, zoomDepth: 7)
        #expect(abs(enter.scale * 7 - 1.15) < 1e-12)
    }
}
