import Testing
import SwiftUI
import ZeusDomain
@testable import ZeusUI

/// `ConstellationPresenter` is a pure projection of `NavigationState` into the chrome the views
/// render — which bottom panel shows, whether the Back pill is up, whether pointer input is live,
/// the breadcrumb, the detached badge, and the live zoom transform. No mutation, no business
/// logic: derive-don't-duplicate over the single source of truth.
struct ConstellationPresenterTests {

    private func presenter(_ state: NavigationState) -> ConstellationPresenter {
        ConstellationPresenter(state: state)
    }

    // MARK: - Bottom panel: terminal on hub/work, Changes on the branch tree (SPEC §7)

    @Test func hubAndWorktreesShowTheTerminal() {
        #expect(presenter(NavigationState(view: .hub)).bottomPanel == .terminal)
        #expect(presenter(NavigationState(view: .work)).bottomPanel == .terminal)
    }

    @Test func branchTreeShowsTheChangesPanel() {
        #expect(presenter(NavigationState(view: .tree)).bottomPanel == .changes)
    }

    // MARK: - Terminal working directory follows the dived-into repo (SPEC §2.6, §7)

    private let home = URL(fileURLWithPath: "/Users/zeus")

    @Test func terminalUsesHomeAtTheHubWithNoProject() {
        let state = NavigationState(view: .hub)
        #expect(presenter(state).terminalWorkingDirectory(home: home) == home)
    }

    @Test func terminalUsesTheDivedIntoRepoPathAtTheWorktreeLevel() {
        let state = NavigationState(view: .work, projectPath: "/code/zeus")
        #expect(presenter(state).terminalWorkingDirectory(home: home)
                == URL(fileURLWithPath: "/code/zeus"))
    }

    // Backing out to the hub leaves `projectPath` set (the reducer never clears it), but the hub
    // isn't inside any repo — the terminal must fall back to home, not the stale path.
    @Test func terminalIgnoresAStaleProjectPathAtTheHub() {
        let state = NavigationState(view: .hub, projectPath: "/code/zeus")
        #expect(presenter(state).terminalWorkingDirectory(home: home) == home)
    }

    // MARK: - Back pill floats only below the hub

    @Test func backPillHiddenAtHubVisibleDeeper() {
        #expect(presenter(NavigationState(view: .hub)).showsBackPill == false)
        #expect(presenter(NavigationState(view: .work)).showsBackPill == true)
        #expect(presenter(NavigationState(view: .tree)).showsBackPill == true)
    }

    // MARK: - Pointer events are disabled while a zoom is mid-flight (idle-only)

    @Test func pointerEnabledOnlyWhenIdle() {
        #expect(presenter(NavigationState(phase: .idle)).pointerEnabled == true)
        #expect(presenter(NavigationState(phase: .leave)).pointerEnabled == false)
        #expect(presenter(NavigationState(phase: .enter)).pointerEnabled == false)
    }

    // Keyboard focus follows the same idle-only gate as pointer input: an arrow/Return must not
    // move focus or activate a node while a zoom is mid-flight (SPEC §7: pointer events disabled
    // off-idle — the same applies to the keyboard so the two input modes can't fight the camera).
    @Test func keyboardEnabledOnlyWhenIdle() {
        #expect(presenter(NavigationState(phase: .idle)).keyboardEnabled == true)
        #expect(presenter(NavigationState(phase: .leave)).keyboardEnabled == false)
        #expect(presenter(NavigationState(phase: .enter)).keyboardEnabled == false)
    }

    // MARK: - Breadcrumb grows Asteris / {project} / {branch} as you dive

    @Test func breadcrumbIsJustTheRootAtHub() {
        #expect(presenter(NavigationState(view: .hub)).breadcrumb == ["Asteris"])
    }

    @Test func breadcrumbAddsProjectAtWorktrees() {
        let state = NavigationState(view: .work, project: "tuntun-api")
        #expect(presenter(state).breadcrumb == ["Asteris", "tuntun-api"])
    }

    @Test func breadcrumbAddsProjectAndBranchAtTree() {
        let state = NavigationState(view: .tree, project: "tuntun-api", worktreeBranch: "develop")
        #expect(presenter(state).breadcrumb == ["Asteris", "tuntun-api", "develop"])
    }

    // MARK: - Detached badge appears once HEAD diverges from the branch tip

    @Test func noDetachedLabelWhenHeadIsTheTip() {
        let state = NavigationState(head: "12ab9c", tip: "12ab9c")
        #expect(presenter(state).detachedLabel == nil)
    }

    @Test func detachedLabelShowsTheCheckedOutHash() {
        let state = NavigationState(head: "aa55fe", tip: "12ab9c")
        #expect(presenter(state).detachedLabel == "detached HEAD @aa55fe")
    }

    // MARK: - The Changes panel shows a HEAD badge vs a Checkout button

    @Test func selectedIsHeadWhenSelectionEqualsHead() {
        #expect(presenter(NavigationState(head: "aa55fe", selected: "aa55fe")).selectedIsHead == true)
        #expect(presenter(NavigationState(head: "aa55fe", selected: "81c3e0")).selectedIsHead == false)
    }

    // MARK: - Live zoom transform: ZoomTransition for the current phase, anchor as a UnitPoint

    @Test func idleStageSettlesToScaleOneAnchoredOnTheEnterOrigin() {
        let state = NavigationState(phase: .idle,
                                    leaveOrigin: StagePoint(x: 260, y: 135),
                                    enterOrigin: StagePoint(x: 520, y: 270))
        let p = presenter(state)
        #expect(p.transition.scale == 1)
        #expect(p.transition.opacity == 1)
        #expect(p.transitionAnchor == UnitPoint(x: 0.5, y: 0.5))   // the enter origin
    }

    @Test func divingInLeavesByScalingUpAboutTheFocalNode() {
        let state = NavigationState(phase: .leave, dir: .inward,
                                    leaveOrigin: StagePoint(x: 260, y: 135),
                                    enterOrigin: StagePoint(x: 520, y: 270))
        let p = presenter(state)
        #expect(p.transition.scale == 7)                            // BIG = default zoomDepth
        #expect(p.transition.opacity == 0)
        #expect(p.transitionAnchor == UnitPoint(x: 0.25, y: 0.25))  // the focal/leave origin
    }

    // MARK: - Regression: the zoom pivots on ONE fixed focal node for the WHOLE transition
    //
    // The prototype (Design/ZeusTerm-Live.dc.html lines 335/340/342) transitions only `transform`
    // and `opacity` — `transform-origin` is never in the transition list, so the pivot SNAPS. The
    // reducer mirrors that by setting leaveOrigin == enterOrigin == focal, so a real dive's anchor
    // is the SAME point in leave, enter, and the idle settle. If those ever diverge — or the view
    // lets SwiftUI interpolate the `scaleEffect` anchor across the cross-transition focal jump —
    // the dive reads as a sideways PAN while zooming in (ConstellationStage snaps the anchor to
    // keep parity; this guards the pure contract that snap relies on).

    @Test func diveAnchorStaysPinnedToOneFocalNodeAcrossEveryPhase() {
        let focal = StagePoint(x: 832, y: 256)            // an OFF-CENTER repo star — worst case for drift
        let idle = NavigationState(view: .hub, phase: .idle)

        let leaving  = NavigationReducer.reduce(idle, .dive(to: .work, focal: focal, context: DiveContext()))
        let entering = NavigationReducer.reduce(leaving, .phaseAdvance)
        let settled  = NavigationReducer.reduce(entering, .phaseSettle)

        let expected = StageGeometry.unitPoint(for: focal)
        #expect(presenter(leaving).state.phase == .leave)
        #expect(presenter(leaving).transitionAnchor == expected)
        #expect(presenter(entering).state.phase == .enter)
        #expect(presenter(entering).transitionAnchor == expected)
        #expect(presenter(settled).state.phase == .idle)
        #expect(presenter(settled).transitionAnchor == expected)
    }
}
