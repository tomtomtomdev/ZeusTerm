import Foundation

/// Pure orchestration use case for the branch-tree level: reads a worktree's branch history through
/// `GitReading` and maps each commit to the `GraphCommit` that `CommitGraphLayout` ranks and places.
/// Mirrors `WorktreeOrbitLoader` — I/O lives in the injected adapter, so it's unit-testable with a
/// stub. First cut shows the checked-out branch's linear history in a single lane; a multi-branch
/// graph (the prototype's cross-lane merges) is a later refinement.
public struct CommitTreeLoader: Sendable {
    /// First-page size for the branch history. The graph paints this many newest commits; scroll
    /// pagination (skip-based, via `GitReading.commits`) is a later refinement (SPEC §2.2).
    public static let pageSize = 100

    private let git: any GitReading

    public init(git: any GitReading) {
        self.git = git
    }

    /// The newest `pageSize` commits reachable from `branch` in the repo at `repoPath`, newest
    /// first, as `GraphCommit`s tagged with that branch (its single lane for now).
    public func load(repoPath: URL, branch: String) async throws -> [GraphCommit] {
        let commits = try await git.commits(forBranch: branch, in: repoPath, limit: Self.pageSize, skip: 0)
        return commits.map {
            GraphCommit(sha: $0.id, summary: $0.summary, branch: branch, parents: $0.parents)
        }
    }
}
