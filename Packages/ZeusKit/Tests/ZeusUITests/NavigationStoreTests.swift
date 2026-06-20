import Testing
import Foundation
import ZeusDomain
@testable import ZeusUI

/// The store's responsibility on top of the pure `NavigationReducer` is to (a) forward actions
/// and (b) *schedule* the timed phase effect after a transition opens. We assert the synchronous
/// pre-effect state right after dispatch (the effect's `Task` is enqueued but hasn't run), then
/// `await` the transition to completion via an `ImmediateClock` — deterministic, no yield racing.
@MainActor
struct NavigationStoreTests {
    private let focal = StagePoint(x: 10, y: 20)

    @Test func selectAndCheckoutForwardToReducer() {
        let store = NavigationStore()                  // default ContinuousClock — these never schedule
        store.dispatch(.selectCommit("aa55fe"))
        #expect(store.state.selected == "aa55fe")

        store.dispatch(.checkout("9f12bb"))
        #expect(store.state.head == "9f12bb")
        #expect(store.state.selected == "9f12bb")
    }

    @Test func reduceMotionDiveSwitchesInstantly() {
        let store = NavigationStore(clock: ImmediateClock())
        store.setReduceMotion(true)

        store.dispatch(.dive(to: .work, focal: focal, context: DiveContext(project: "tuntun-api")))
        #expect(store.state.phase == .idle)            // no transition scheduled under reduce motion
        #expect(store.state.view == .work)
        #expect(store.state.project == "tuntun-api")
    }

    @Test func diveLeavesImmediatelyThenAutoSettlesToIdle() async {
        let store = NavigationStore(clock: ImmediateClock())

        store.dispatch(.dive(to: .work, focal: focal, context: DiveContext(project: "tuntun-api")))
        // Synchronous: the effect is scheduled but hasn't run — still mid-leave on the focal node.
        #expect(store.state.phase == .leave)
        #expect(store.state.view == .hub)              // view flips only at phaseAdvance
        #expect(store.state.leaveOrigin == focal)

        await store.waitForTransition()                // leave → enter → idle runs to completion
        #expect(store.state.phase == .idle)
        #expect(store.state.view == .work)
        #expect(store.state.project == "tuntun-api")   // context applied at phaseAdvance
    }

    @Test func diveWhileTransitioningIsIgnored() async {
        let store = NavigationStore(clock: ImmediateClock())

        store.dispatch(.dive(to: .work, focal: focal, context: DiveContext(project: "a")))
        let mid = store.state                          // phase == .leave, origins == [focal]
        store.dispatch(.dive(to: .tree, focal: StagePoint(x: 99, y: 99), context: DiveContext(project: "b")))
        #expect(store.state == mid)                    // rejected off-idle, before the effect runs

        await store.waitForTransition()
        #expect(store.state.phase == .idle)
        #expect(store.state.view == .work)             // settled into the FIRST dive's target
        #expect(store.state.project == "a")
    }

    @Test func backAlsoSchedulesATransition() async {
        let store = NavigationStore(
            state: NavigationState(view: .tree, origins: [StagePoint(x: 1, y: 1), focal]),
            clock: ImmediateClock())

        store.dispatch(.back)
        #expect(store.state.phase == .leave)           // back schedules a transition too
        #expect(store.state.leaveOrigin == focal)      // pivots on the popped origin

        await store.waitForTransition()
        #expect(store.state.phase == .idle)
        #expect(store.state.view == .work)
    }
}
