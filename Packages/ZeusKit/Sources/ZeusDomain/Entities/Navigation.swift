import Foundation

/// The three constellation zoom levels (SPEC §7).
public enum Level: Sendable, Hashable { case hub, work, tree }

/// Context carried by a dive: what to select once the incoming level mounts.
public struct DiveContext: Sendable, Hashable {
    public var project: String?
    /// The repo's filesystem path (the hub star's `id`) — carried so the worktree level can load
    /// that repo's real git data. Distinct from `project`, which is the human display name.
    public var projectPath: String?
    public var worktreeBranch: String?
    public var tip: String?     // when diving into a worktree, HEAD/selected reset to this
    public init(project: String? = nil, projectPath: String? = nil,
                worktreeBranch: String? = nil, tip: String? = nil) {
        self.project = project; self.projectPath = projectPath
        self.worktreeBranch = worktreeBranch; self.tip = tip
    }
}

/// Navigation intents. Phase actions (`phaseAdvance`/`phaseSettle`) are dispatched by the
/// store on a timer but flow through the same pure reducer so every transition is testable.
public enum NavigationAction: Sendable {
    case dive(to: Level, focal: StagePoint, context: DiveContext)
    case back
    case backTo(Level)
    case selectCommit(String)
    case checkout(String)
    /// The branch tip became known after its commits loaded (real git) — land HEAD/selected on it.
    case branchTipResolved(String)
    case phaseAdvance   // leave → enter (flips view, applies context, swaps origins)
    case phaseSettle    // enter → idle
}

/// The whole navigation state — drives the stage transform and the visible level.
public struct NavigationState: Sendable, Hashable {
    public var view: Level
    public var phase: ZoomPhase
    public var dir: ZoomDirection
    public var leaveOrigin: StagePoint
    public var enterOrigin: StagePoint
    public var origins: [StagePoint]      // focal-node stack, one per level dived into
    public var project: String?
    /// Filesystem path of the dived-into repo — the key the worktree level loads real git from.
    public var projectPath: String?
    public var worktreeBranch: String?
    public var head: String               // checked-out commit (visual-only checkout)
    public var selected: String           // commit shown in the Changes panel
    public var tip: String                // branch tip; HEAD != tip ⇒ detached
    public var reduceMotion: Bool

    // Transition target applied at `phaseAdvance` (reducer-internal machinery).
    var pendingView: Level? = nil
    var pendingOrigins: [StagePoint]? = nil
    var pendingContext: DiveContext? = nil

    public var detached: Bool { head != tip }

    public init(view: Level = .hub,
                phase: ZoomPhase = .idle,
                dir: ZoomDirection = .inward,
                leaveOrigin: StagePoint = StagePoint(x: 520, y: 262),
                enterOrigin: StagePoint = StagePoint(x: 520, y: 262),
                origins: [StagePoint] = [],
                project: String? = nil,
                projectPath: String? = nil,
                worktreeBranch: String? = nil,
                head: String = "",
                selected: String = "",
                tip: String = "",
                reduceMotion: Bool = false) {
        self.view = view; self.phase = phase; self.dir = dir
        self.leaveOrigin = leaveOrigin; self.enterOrigin = enterOrigin; self.origins = origins
        self.project = project; self.projectPath = projectPath
        self.worktreeBranch = worktreeBranch
        self.head = head; self.selected = selected; self.tip = tip
        self.reduceMotion = reduceMotion
    }

    public static let initial = NavigationState()
}
