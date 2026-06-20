import Foundation
import ZeusDomain

/// Seeded sample fixtures that mirror the design prototype (`Design/ZeusTerm-Live.dc.html`),
/// so the whole constellation renders before the P3 scanner feeds real data. The raw fixtures
/// are fed through the pure ZeusDomain layout use cases to produce each laid-out level.
///
/// Commit `parents` are derived from the prototype's tree edges: the topological rank (computed
/// by `CommitGraphLayout`) reproduces the prototype's intended newest-on-top ordering without
/// hand-assigned time indices.
public enum SampleConstellationData {

    // MARK: - Hub level inputs

    public static let hubInput = HubInput(name: "tuntun-mono", center: StagePoint(x: 512, y: 252))

    public static let clusters: [ClusterInput] = [
        ClusterInput(type: "Frontend", center: StagePoint(x: 205, y: 148), spread: 70, members: [
            MemberInput(name: "tuntun-web", status: .ahead),
            MemberInput(name: "checkout-ui", status: .dirty),
            MemberInput(name: "design-system", status: .clean),
            MemberInput(name: "admin-portal", status: .clean),
            MemberInput(name: "marketing-site", status: .behind),
        ]),
        ClusterInput(type: "Backend", center: StagePoint(x: 498, y: 118), spread: 82, members: [
            MemberInput(name: "tuntun-api", status: .dirty),
            MemberInput(name: "payments-svc", status: .clean),
            MemberInput(name: "auth-gateway", status: .ahead),
            MemberInput(name: "ledger-go", status: .clean),
            MemberInput(name: "notif-worker", status: .untracked),
        ]),
        ClusterInput(type: "iOS", center: StagePoint(x: 788, y: 158), spread: 56, members: [
            MemberInput(name: "Tuntun-iOS", status: .clean),
            MemberInput(name: "WalletKit", status: .dirty),
            MemberInput(name: "ScanSDK", status: .clean),
        ]),
        ClusterInput(type: "macOS", center: StagePoint(x: 862, y: 342), spread: 52, members: [
            MemberInput(name: "ZeusTerm", status: .dirty),
            MemberInput(name: "MenuBarX", status: .clean),
            MemberInput(name: "ColorPick", status: .ahead),
        ]),
        ClusterInput(type: "Mobile", center: StagePoint(x: 608, y: 408), spread: 58, members: [
            MemberInput(name: "tuntun-flutter", status: .behind),
            MemberInput(name: "driver-rn", status: .clean),
            MemberInput(name: "kiosk-app", status: .dirty),
        ]),
        ClusterInput(type: "Scripts", center: StagePoint(x: 218, y: 392), spread: 64, members: [
            MemberInput(name: "dotfiles", status: .clean),
            MemberInput(name: "deploy-kit", status: .clean),
            MemberInput(name: "db-migrate", status: .untracked),
            MemberInput(name: "backups", status: .clean),
        ]),
    ]

    // MARK: - Worktree (orbit) level inputs

    public static let worktreeCenter = StagePoint(x: 512, y: 256)

    public static let rings: [RingSpec] = [
        RingSpec(radius: 115, count: 3, angleOffset: 0.4),
        RingSpec(radius: 180, count: 4, angleOffset: 0.85),
        RingSpec(radius: 242, count: 3, angleOffset: 0.15),
    ]

    public static let worktrees: [WorktreeInput] = [
        WorktreeInput(branch: "hotfix/payment-retry", name: "api-hotfix", status: .dirty),
        WorktreeInput(branch: "review/pr-482", name: "api-review", status: .clean),
        WorktreeInput(branch: "perf/db-pool", name: "api-perf", status: .ahead),
        WorktreeInput(branch: "feature/oauth-pkce", name: "api-auth", status: .dirty),
        WorktreeInput(branch: "release/1.4", name: "api-rel", status: .clean),
        WorktreeInput(branch: "fix/cache-ttl", name: "api-cache", status: .behind),
        WorktreeInput(branch: "chore/go-1.22", name: "api-chore", status: .clean),
        WorktreeInput(branch: "spike/grpc", name: "api-spike", status: .untracked),
        WorktreeInput(branch: "docs/api-v2", name: "api-docs", status: .clean),
        WorktreeInput(branch: "feature/webhooks", name: "api-wh", status: .ahead),
    ]

    // MARK: - Branch-tree level inputs

    /// Column x per branch lane (the prototype's hand-placed lane positions).
    public static let lanes: [String: Double] = [
        "cache": 300, "main": 430, "develop": 580, "auth": 720,
    ]

    public static let headSHA = "12ab9c"   // the branch tip; HEAD resets here on diving into a worktree
    public static let tipSHA = "12ab9c"
    public static let projectName = "tuntun-api"
    public static let defaultWorktreeBranch = "develop"

    /// 13 commits across 4 lanes. `parents` encode the graph the prototype drew with its edges,
    /// including the two merges (`aa55fe` ← feature/auth, `9f12bb` ← fix/cache).
    public static let commits: [GraphCommit] = [
        GraphCommit(sha: "12ab9c", summary: "session refactor",   branch: "develop", parents: ["aa55fe"]),
        GraphCommit(sha: "aa55fe", summary: "merge feature/auth", branch: "develop", parents: ["81c3e0", "90ab33"]),
        GraphCommit(sha: "81c3e0", summary: "api v2 routes",       branch: "develop", parents: ["2b9f44"]),
        GraphCommit(sha: "2b9f44", summary: "feature flags",       branch: "develop", parents: ["9f12bb"]),
        GraphCommit(sha: "90ab33", summary: "token rotation",      branch: "auth",    parents: ["77de10"]),
        GraphCommit(sha: "77de10", summary: "oauth pkce",          branch: "auth",    parents: ["81c3e0"]),
        GraphCommit(sha: "5fa0cd", summary: "release 1.4",         branch: "main",    parents: ["9f12bb"]),
        GraphCommit(sha: "9f12bb", summary: "merge fix/cache",     branch: "main",    parents: ["c0d4aa", "cc09aa"]),
        GraphCommit(sha: "c0d4aa", summary: "auth scaffold",       branch: "main",    parents: ["7b2e10"]),
        GraphCommit(sha: "7b2e10", summary: "ci pipeline",         branch: "main",    parents: ["a1f3c9"]),
        GraphCommit(sha: "a1f3c9", summary: "init monorepo",       branch: "main",    parents: []),
        GraphCommit(sha: "cc09aa", summary: "invalidate keys",     branch: "cache",   parents: ["5512ee"]),
        GraphCommit(sha: "5512ee", summary: "redis ttl bug",       branch: "cache",   parents: ["c0d4aa"]),
    ]

    // MARK: - Laid-out levels (fixtures → pure use cases)

    public static var hub: ConstellationHub {
        ConstellationLayout().buildHub(clusters: clusters, hub: hubInput)
    }

    public static var orbits: ConstellationOrbits {
        ConstellationLayout().buildOrbits(center: worktreeCenter, worktrees: worktrees, rings: rings)
    }

    public static var tree: ConstellationTree {
        CommitGraphLayout().buildTree(commits: commits, lanes: lanes, head: headSHA)
    }
}
