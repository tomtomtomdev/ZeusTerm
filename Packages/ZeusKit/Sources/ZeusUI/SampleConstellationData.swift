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

    public static let hubInput = HubInput(name: "tuntun-mono", center: HubGeometry.center)

    /// Builds a sample cluster at its canonical `HubGeometry` slot — center/spread come from the
    /// single source of truth, so the sample can't drift from the real `HubModelBuilder` layout.
    private static func cluster(_ type: RepoType, _ members: [MemberInput]) -> ClusterInput {
        let slot = HubGeometry.slot(for: type)
        return ClusterInput(type: type.displayName, center: slot.center,
                            spread: slot.spread, members: members)
    }

    public static let clusters: [ClusterInput] = [
        cluster(.frontend, [
            MemberInput(name: "tuntun-web", status: .ahead),
            MemberInput(name: "checkout-ui", status: .dirty),
            MemberInput(name: "design-system", status: .clean),
            MemberInput(name: "admin-portal", status: .clean),
            MemberInput(name: "marketing-site", status: .behind),
        ]),
        cluster(.backend, [
            MemberInput(name: "tuntun-api", status: .dirty),
            MemberInput(name: "payments-svc", status: .clean),
            MemberInput(name: "auth-gateway", status: .ahead),
            MemberInput(name: "ledger-go", status: .clean),
            MemberInput(name: "notif-worker", status: .untracked),
        ]),
        cluster(.ios, [
            MemberInput(name: "Tuntun-iOS", status: .clean),
            MemberInput(name: "WalletKit", status: .dirty),
            MemberInput(name: "ScanSDK", status: .clean),
        ]),
        cluster(.macos, [
            MemberInput(name: "Asteris", status: .dirty),
            MemberInput(name: "MenuBarX", status: .clean),
            MemberInput(name: "ColorPick", status: .ahead),
        ]),
        cluster(.mobile, [
            MemberInput(name: "tuntun-flutter", status: .behind),
            MemberInput(name: "driver-rn", status: .clean),
            MemberInput(name: "kiosk-app", status: .dirty),
        ]),
        cluster(.scripts, [
            MemberInput(name: "dotfiles", status: .clean),
            MemberInput(name: "deploy-kit", status: .clean),
            MemberInput(name: "db-migrate", status: .untracked),
            MemberInput(name: "backups", status: .clean),
        ]),
    ]

    // MARK: - Worktree (orbit) level inputs

    /// The orbit center is owned by `WorktreeOrbitStore` (the real orbit level) — reference it so the
    /// sample can't drift from the center a live repo's worktrees orbit.
    public static let worktreeCenter = WorktreeOrbitStore.defaultCenter


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

    // MARK: - Sample diffs for the Changes panel (visual-only until git diff feeds it)

    private static let diffs: [String: CommitDiff] = [
        "12ab9c": CommitDiff(sha: "12ab9c", files: [
            FileChange(path: "Sources/Session/SessionStore.swift", status: .modified, additions: 38, deletions: 12),
            FileChange(path: "Sources/Session/TokenCache.swift", status: .added, additions: 64, deletions: 0),
            FileChange(path: "Tests/SessionStoreTests.swift", status: .modified, additions: 21, deletions: 4),
        ], patch: """
        diff --git a/Sources/Session/SessionStore.swift b/Sources/Session/SessionStore.swift
        @@ -18,7 +18,9 @@ final class SessionStore {
             func refresh() async throws {
        -        let token = try await api.token()
        +        let token = try await cache.token(or: api.token)
        +        cache.store(token)
                 self.current = token
             }
        """),
        "aa55fe": CommitDiff(sha: "aa55fe", files: [
            FileChange(path: "Sources/Auth/OAuthFlow.swift", status: .added, additions: 142, deletions: 0),
            FileChange(path: "Sources/Auth/Keychain.swift", status: .modified, additions: 9, deletions: 3),
        ], patch: """
        diff --git a/Sources/Auth/OAuthFlow.swift b/Sources/Auth/OAuthFlow.swift
        @@ -0,0 +1,4 @@
        +struct OAuthFlow {
        +    let pkce: PKCEChallenge
        +    func authorize() async throws -> AuthCode { ... }
        +}
        """),
    ]

    /// The changed files + patch for a commit; an empty (no-change) diff for unknown shas.
    public static func diff(forSHA sha: String) -> CommitDiff {
        diffs[sha] ?? CommitDiff(sha: sha, files: [], patch: "")
    }

    // MARK: - Laid-out levels (fixtures → pure use cases)

    public static var hub: ConstellationHub {
        ConstellationLayout().buildHub(clusters: clusters, hub: hubInput)
    }

    public static var orbits: SideOnOrbits {
        SideOnOrbitPlanner().layout(center: worktreeCenter, name: projectName,
                                    status: worktrees.first?.status, worktrees: worktrees)
    }

    public static var tree: ConstellationTree {
        // Compress the rows so all 12 topological ranks fit inside the 540px stage (the layout's
        // 80px default would push the oldest commits below the stage and clip them).
        CommitGraphLayout().buildTree(commits: commits, lanes: lanes, head: headSHA,
                                      rowHeight: 40, topY: 50)
    }
}
