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

    // MARK: - Breadcrumb grows ZeusTerm / {project} / {branch} as you dive

    @Test func breadcrumbIsJustTheRootAtHub() {
        #expect(presenter(NavigationState(view: .hub)).breadcrumb == ["ZeusTerm"])
    }

    @Test func breadcrumbAddsProjectAtWorktrees() {
        let state = NavigationState(view: .work, project: "tuntun-api")
        #expect(presenter(state).breadcrumb == ["ZeusTerm", "tuntun-api"])
    }

    @Test func breadcrumbAddsProjectAndBranchAtTree() {
        let state = NavigationState(view: .tree, project: "tuntun-api", worktreeBranch: "develop")
        #expect(presenter(state).breadcrumb == ["ZeusTerm", "tuntun-api", "develop"])
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
}
