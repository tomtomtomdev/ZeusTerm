import SwiftUI
import ZeusDomain

/// A pure projection of `NavigationState` into the chrome the constellation views render. It owns
/// no state and no business logic — every property is derived from the store's single source of
/// truth, so the views stay declarative and the derivations stay unit-tested (SPEC §7).
public struct ConstellationPresenter {

    /// Which surface fills the bottom panel for the current level.
    public enum BottomPanel: Sendable, Hashable { case terminal, changes }

    public let state: NavigationState

    public init(state: NavigationState) {
        self.state = state
    }

    /// Hub & worktree levels show the PTY terminal; the branch tree swaps in the Changes panel.
    public var bottomPanel: BottomPanel {
        state.view == .tree ? .changes : .terminal
    }

    /// The frosted ‹ Back pill floats top-left only below the hub.
    public var showsBackPill: Bool {
        state.view != .hub
    }

    /// Pointer events are disabled while a zoom transition is in flight ("idle-only").
    public var pointerEnabled: Bool {
        state.phase == .idle
    }

    /// The root workspace label shown first in the breadcrumb.
    public static let root = "ZeusTerm"

    /// `ZeusTerm / {project} / {branch}` — grows one segment per level dived into.
    public var breadcrumb: [String] {
        var crumbs = [Self.root]
        if state.view == .work || state.view == .tree, let project = state.project {
            crumbs.append(project)
        }
        if state.view == .tree, let branch = state.worktreeBranch {
            crumbs.append(branch)
        }
        return crumbs
    }

    /// Shown in the topbar once HEAD diverges from the branch tip (visual-only checkout).
    public var detachedLabel: String? {
        state.detached ? "detached HEAD @\(state.head)" : nil
    }

    /// Whether the selected commit is HEAD — drives the Changes panel's ● HEAD badge vs Checkout.
    public var selectedIsHead: Bool {
        state.selected == state.head
    }

    /// The live stage transform for the current phase/direction (pure zoom math from ZeusDomain).
    public var transition: ZoomTransition {
        ZoomTransition.make(phase: state.phase,
                            dir: state.dir,
                            leaveOrigin: state.leaveOrigin,
                            enterOrigin: state.enterOrigin,
                            reduceMotion: state.reduceMotion)
    }

    /// The transition's focal anchor mapped into the stage's unit space for `scaleEffect`.
    public var transitionAnchor: UnitPoint {
        StageGeometry.unitPoint(for: transition.anchor)
    }
}
