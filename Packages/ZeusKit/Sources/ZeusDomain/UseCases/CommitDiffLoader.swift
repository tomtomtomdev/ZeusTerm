import Foundation

/// Pure orchestration use case for the branch-tree Changes panel (slice 6, SPEC §7 View 3): reads
/// one commit's changed files + unified diff through `GitReading.diff`. Mirrors `CommitTreeLoader` —
/// the `git` read lives in the injected adapter and runs off the main actor, so the UI store stays a
/// thin "when + publish" coordinator and this stays unit-testable with a stub (no git CLI).
public struct CommitDiffLoader: Sendable {
    private let git: any GitReading

    public init(git: any GitReading) {
        self.git = git
    }

    /// The changed files + unified diff for `sha` in the repo at `repoPath`.
    public func load(repoPath: URL, sha: String) async throws -> CommitDiff {
        try await git.diff(forCommit: sha, in: repoPath)
    }
}
