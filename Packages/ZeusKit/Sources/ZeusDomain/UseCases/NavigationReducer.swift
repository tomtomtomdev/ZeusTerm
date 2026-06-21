import Foundation

/// Pure reducer for the constellation zoom navigation (SPEC §7). All state mutation lives
/// here — including phase transitions — so the camera logic is fully unit-testable. The
/// store owns only *when* `phaseAdvance`/`phaseSettle` fire. Dives/backs are ignored while
/// a transition is in flight (the off-idle guard), matching "pointer events disabled off-idle".
public enum NavigationReducer {
    private static let defaultOrigin = StagePoint(x: 520, y: 262)

    public static func reduce(_ state: NavigationState, _ action: NavigationAction) -> NavigationState {
        var s = state
        switch action {
        case let .dive(to, focal, context):
            guard s.phase == .idle else { return state }   // off-idle guard
            let pushed = s.origins + [focal]
            s.dir = .inward
            if s.reduceMotion {
                s.view = to
                s.origins = pushed
                s.phase = .idle
                apply(context, to: &s)
            } else {
                s.phase = .leave
                s.leaveOrigin = focal
                s.enterOrigin = focal
                s.origins = pushed
                s.pendingView = to
                s.pendingOrigins = pushed
                s.pendingContext = context
            }

        case .back:
            guard s.phase == .idle, let parent = parentLevel(of: s.view) else { return state }
            var remaining = s.origins
            let focal = remaining.popLast() ?? defaultOrigin
            beginBackOut(&s, target: parent, newOrigins: remaining, focal: focal)

        case let .backTo(target):
            guard s.phase == .idle else { return state }
            let depth = depth(of: target)
            let focal = depth < s.origins.count ? s.origins[depth] : defaultOrigin
            beginBackOut(&s, target: target, newOrigins: Array(s.origins.prefix(depth)), focal: focal)

        case let .selectCommit(sha):
            s.selected = sha

        case let .checkout(sha):
            s.head = sha
            s.selected = sha

        case .phaseAdvance:
            guard s.phase == .leave else { return state }
            s.phase = .enter
            if let view = s.pendingView { s.view = view }
            if let origins = s.pendingOrigins { s.origins = origins }
            if let context = s.pendingContext { apply(context, to: &s) }
            s.pendingView = nil; s.pendingOrigins = nil; s.pendingContext = nil

        case .phaseSettle:
            guard s.phase == .enter else { return state }
            s.phase = .idle
        }
        return s
    }

    /// Backing out: pivot on `focal`, flip to `target` at `phaseAdvance` (origins applied then).
    private static func beginBackOut(_ s: inout NavigationState,
                                     target: Level, newOrigins: [StagePoint], focal: StagePoint) {
        s.dir = .outward
        if s.reduceMotion {
            s.view = target
            s.origins = newOrigins
            s.phase = .idle
        } else {
            s.phase = .leave
            s.leaveOrigin = focal
            s.enterOrigin = focal
            s.pendingView = target
            s.pendingOrigins = newOrigins
            s.pendingContext = nil
        }
    }

    private static func apply(_ context: DiveContext, to s: inout NavigationState) {
        if let project = context.project { s.project = project }
        if let projectPath = context.projectPath { s.projectPath = projectPath }
        if let branch = context.worktreeBranch { s.worktreeBranch = branch }
        if let tip = context.tip { s.tip = tip; s.head = tip; s.selected = tip }
    }

    private static func parentLevel(of level: Level) -> Level? {
        switch level {
        case .tree: return .work
        case .work: return .hub
        case .hub:  return nil
        }
    }

    private static func depth(of level: Level) -> Int {
        switch level {
        case .hub:  return 0
        case .work: return 1
        case .tree: return 2
        }
    }
}
