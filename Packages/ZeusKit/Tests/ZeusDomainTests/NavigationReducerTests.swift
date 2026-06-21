import Testing
import Foundation
@testable import ZeusDomain

struct NavigationReducerTests {
    private let p1 = StagePoint(x: 100, y: 100)
    private let p2 = StagePoint(x: 200, y: 200)

    private func reduce(_ state: NavigationState, _ action: NavigationAction) -> NavigationState {
        NavigationReducer.reduce(state, action)
    }

    @Test func diveGoesThroughLeaveEnterIdleApplyingContextAtAdvance() {
        var s = NavigationState.initial   // hub / idle

        s = reduce(s, .dive(to: .work, focal: p1, context: DiveContext(project: "tuntun-api")))
        #expect(s.phase == .leave)
        #expect(s.dir == .inward)
        #expect(s.view == .hub)            // view flips only at phaseAdvance
        #expect(s.leaveOrigin == p1)
        #expect(s.origins == [p1])         // focal pushed

        s = reduce(s, .phaseAdvance)
        #expect(s.phase == .enter)
        #expect(s.view == .work)
        #expect(s.project == "tuntun-api")

        s = reduce(s, .phaseSettle)
        #expect(s.phase == .idle)
    }

    @Test func diveCarriesTheRepoPathSoTheOrbitLevelCanLoadRealGit() {
        var s = NavigationState.initial   // hub / idle

        s = reduce(s, .dive(to: .work, focal: p1,
                            context: DiveContext(project: "tuntun-api",
                                                 projectPath: "/Users/me/code/tuntun-api")))
        // Path, like the display name, is applied at phaseAdvance for the animated dive.
        s = reduce(s, .phaseAdvance)
        #expect(s.view == .work)
        #expect(s.project == "tuntun-api")
        #expect(s.projectPath == "/Users/me/code/tuntun-api")
    }

    @Test func diveIsIgnoredWhileNotIdle() {
        var s = NavigationState.initial
        s = reduce(s, .dive(to: .work, focal: p1, context: DiveContext(project: "a")))
        let mid = s                         // phase == .leave
        s = reduce(s, .dive(to: .tree, focal: p2, context: DiveContext(project: "b")))
        #expect(s == mid)                   // second dive rejected off-idle
    }

    @Test func diveToTreeResetsHeadAndSelectedToTip() {
        var s = NavigationState.initial
        s = reduce(s, .dive(to: .tree, focal: p1,
                            context: DiveContext(worktreeBranch: "feature/oauth", tip: "12ab9c")))
        s = reduce(s, .phaseAdvance)
        #expect(s.view == .tree)
        #expect(s.worktreeBranch == "feature/oauth")
        #expect(s.head == "12ab9c")
        #expect(s.selected == "12ab9c")
        #expect(s.detached == false)
    }

    @Test func backPopsTheTopOriginAndReturnsToParent() {
        var s = NavigationState.initial
        s.view = .tree
        s.origins = [p1, p2]

        s = reduce(s, .back)
        #expect(s.phase == .leave)
        #expect(s.dir == .outward)
        #expect(s.leaveOrigin == p2)        // pivots on the popped (top) origin

        s = reduce(s, .phaseAdvance)
        #expect(s.view == .work)
        #expect(s.origins == [p1])
    }

    @Test func backToHubMultiHopPivotsOnTargetDepthOrigin() {
        var s = NavigationState.initial
        s.view = .tree
        s.origins = [p1, p2]                // [hub-boundary, work-boundary]

        s = reduce(s, .backTo(.hub))
        #expect(s.leaveOrigin == p1)        // origin at target depth 0, not the top
        s = reduce(s, .phaseAdvance)
        #expect(s.view == .hub)
        #expect(s.origins == [])
    }

    @Test func selectAndCheckoutAreVisualOnly() {
        var s = NavigationState.initial
        s.tip = "12ab9c"; s.head = "12ab9c"; s.selected = "12ab9c"

        s = reduce(s, .selectCommit("aa55fe"))
        #expect(s.selected == "aa55fe")
        #expect(s.head == "12ab9c")          // selecting doesn't move HEAD
        #expect(s.detached == false)

        s = reduce(s, .checkout("9f12bb"))
        #expect(s.head == "9f12bb")
        #expect(s.selected == "9f12bb")
        #expect(s.detached == true)          // moved away from tip
    }

    @Test func reduceMotionDiveAppliesImmediatelyWithoutPhases() {
        var s = NavigationState.initial
        s.reduceMotion = true

        s = reduce(s, .dive(to: .work, focal: p1, context: DiveContext(project: "tuntun-api")))
        #expect(s.phase == .idle)
        #expect(s.view == .work)
        #expect(s.project == "tuntun-api")
        #expect(s.origins == [p1])
    }
}
