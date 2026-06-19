import Foundation

/// Pure use case: turns git model data into the display tree
/// (Repo → Worktree → Branch → Commits). No side effects, fully unit-tested.
public struct RepoTreeBuilder: Sendable {
    public init() {}

    /// Builds one tree per project's repository.
    public func build(from projects: [Project]) -> [TreeNode] {
        projects.map { build(from: $0.repository) }
    }

    public func build(from repository: Repository) -> TreeNode {
        TreeNode(
            id: "repo:" + repository.commonDir.path,
            kind: .repository,
            title: repository.name,
            subtitle: repository.commonDir.path,
            children: repository.worktrees.map(node(for:))
        )
    }

    private func node(for worktree: Worktree) -> TreeNode {
        TreeNode(
            id: "worktree:" + worktree.path.path,
            kind: .worktree,
            title: worktree.path.lastPathComponent,
            subtitle: worktree.isMain ? "main worktree" : worktree.path.path,
            badge: worktree.isLocked ? "locked" : nil,
            children: worktree.branches.map(node(for:))
        )
    }

    private func node(for branch: Branch) -> TreeNode {
        var badges: [String] = []
        if branch.isCurrent { badges.append("current") }
        if branch.ahead > 0 { badges.append("↑\(branch.ahead)") }
        if branch.behind > 0 { badges.append("↓\(branch.behind)") }
        return TreeNode(
            id: "branch:" + branch.name,
            kind: .branch,
            title: branch.name,
            subtitle: branch.upstream,
            badge: badges.isEmpty ? nil : badges.joined(separator: " "),
            children: branch.commits.map(node(for:))
        )
    }

    private func node(for commit: Commit) -> TreeNode {
        TreeNode(
            id: "commit:" + commit.id,
            kind: .commit,
            title: commit.summary,
            subtitle: String(commit.id.prefix(7)) + " · " + commit.authorName
        )
    }
}
