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

    @ObservationIgnored private let loader: CommitTreeLoader
    @ObservationIgnored private let layout: CommitGraphLayout
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    public init(loader: CommitTreeLoader, layout: CommitGraphLayout = CommitGraphLayout()) {
        self.loader = loader
        self.layout = layout
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
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let commits = try await self.loader.load(repoPath: repoPath, branch: branch)
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
