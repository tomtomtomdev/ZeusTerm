import Foundation
import Observation
import ZeusDomain

/// Drives the branch-tree level: when the user dives into a worktree, it runs the pure
/// `CommitTreeLoader` (off-main) for that worktree's branch and publishes the laid-out
/// `ConstellationTree` plus the branch `tip` (newest commit). The shell lands HEAD/selected on the
/// tip via `.branchTipResolved` once it's known. Owns one level's data, like `HubDataStore` /
/// `WorktreeOrbitStore`.
///
/// `CommitTreeLoader.load` is a nonisolated async function, so the `git log` read runs off the main
/// actor; only the publication resumes here on `@MainActor`. Like `WorktreeOrbitStore`, a new dive
/// supersedes any in-flight load (cancellable single task + clear-on-start + cancel-guarded publish)
/// so a slower earlier branch can't clobber a newer one.
@MainActor
@Observable
public final class CommitTreeStore {
    /// Single-branch lane x in stage space (the prototype's multi-lane graph is a later refinement).
    public static let lane: Double = 520
    /// Newest commits shown — enough to fill the 540pt stage at the prototype's compressed row
    /// height; older commits + scroll pagination are a later refinement (SPEC §2.2).
    public static let maxVisibleCommits = 12

    /// nil until the first branch finishes loading and again while a new branch loads.
    public private(set) var tree: ConstellationTree?
    /// The branch's newest commit sha once loaded; nil while loading, on failure, or empty history.
    public private(set) var tip: String?

    /// nil only for a fixture store (no git): then `load` publishes the seeded tree/tip instead.
    @ObservationIgnored private let loader: CommitTreeLoader?
    @ObservationIgnored private let layout: CommitGraphLayout
    /// Pre-laid-out tree + tip for a fixture store; nil for a real (loader-backed) store.
    @ObservationIgnored private let fixtureTree: ConstellationTree?
    @ObservationIgnored private let fixtureTip: String?
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    public init(loader: CommitTreeLoader, layout: CommitGraphLayout = CommitGraphLayout()) {
        self.loader = loader
        self.layout = layout
        self.fixtureTree = nil
        self.fixtureTip = nil
    }

    /// Fixture seam (slice 7(b)): a store pre-seeded with an already-laid-out tree + branch tip and
    /// no loader, so it renders a fixed branch level (previews / ZoomSpike / `-uiTestFixtures`)
    /// without a `git log`. It still publishes the tip *asynchronously* on `load` — exactly as the
    /// real store does — so the shell's `.onChange(tip)` fires `.branchTipResolved` and HEAD/selected
    /// land on the tip.
    public init(fixtureTree: ConstellationTree, fixtureTip: String) {
        self.loader = nil
        self.layout = CommitGraphLayout()
        self.fixtureTree = fixtureTree
        self.fixtureTip = fixtureTip
    }

    deinit { loadTask?.cancel() }

    /// Loads `branch`'s history for the repo at `repoPath` and publishes the laid-out tree + tip.
    /// Clears the previous branch's tree up front and cancels any in-flight load, so the level
    /// reflects this dive and a slower earlier load can't clobber it. A failed read publishes an
    /// empty tree (no nodes) with no tip.
    public func load(repoPath: URL, branch: String) {
        loadTask?.cancel()
        tree = nil
        tip = nil
        guard let loader else {                       // fixture store: emit the seeded level, no git
            loadTask = Task { [weak self] in
                guard let self, !Task.isCancelled else { return }   // a newer dive supersedes this one
                self.tree = self.fixtureTree
                self.tip = self.fixtureTip
            }
            return
        }
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let commits = try await loader.load(repoPath: repoPath, branch: branch)
                if Task.isCancelled { return }
                self.publish(commits, branch: branch)
            } catch {
                if Task.isCancelled { return }
                self.tree = ConstellationTree(nodes: [], edges: [])
                self.tip = nil
            }
        }
    }

    /// Test seam: await the in-flight load (no-op if none), mirroring `WorktreeOrbitStore.waitForLoad()`.
    public func waitForLoad() async { await loadTask?.value }

    private func publish(_ commits: [GraphCommit], branch: String) {
        tip = commits.first?.sha
        let visible = Array(commits.prefix(Self.maxVisibleCommits))
        tree = layout.buildTree(commits: visible,
                                lanes: [branch: Self.lane],
                                head: tip ?? "",
                                rowHeight: 40, topY: 50)
    }
}
