import Foundation

/// Pure orchestration use case for the worktree (orbit) level: reads a repo's real worktrees and
/// each one's working-tree status through `GitReading`, mapping them to the `WorktreeInput`s the
/// layout places as satellites. Mirrors `HubDataLoader` — I/O lives in the injected adapter, so
/// this is unit-testable with a stub. The store turns the result into a laid-out `SideOnOrbits`
/// via `SideOnOrbitPlanner`.
public struct WorktreeOrbitLoader: Sendable {
    /// Branch label for a worktree with no checked-out branch (detached HEAD).
    static let detachedLabel = "(detached)"

    private let git: any GitReading

    public init(git: any GitReading) {
        self.git = git
    }

    /// Worktrees of the repo at `repoPath`, in `git worktree list` order. A failed read of any one
    /// worktree's status degrades to `.clean` (neutral) so a single bad worktree never blanks the
    /// level; an unreadable repository propagates, leaving the store's current orbits in place.
    public func load(repoPath: URL) async throws -> [WorktreeInput] {
        let repository = try await git.readRepository(at: repoPath)
        var inputs: [WorktreeInput] = []
        inputs.reserveCapacity(repository.worktrees.count)
        for worktree in repository.worktrees {
            let status = (try? await git.status(at: worktree.path)) ?? .clean
            let branch = worktree.currentBranch?.name ?? Self.detachedLabel
            inputs.append(WorktreeInput(branch: branch,
                                        name: worktree.path.lastPathComponent,
                                        status: status))
        }
        return inputs
    }
}
