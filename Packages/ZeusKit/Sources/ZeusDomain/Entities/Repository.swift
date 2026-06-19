import Foundation

/// A git repository, identified by its common dir, holding one or more worktrees.
public struct Repository: Identifiable, Sendable, Hashable {
    public var id: URL { commonDir }
    public var name: String
    public var commonDir: URL
    public var worktrees: [Worktree]

    public init(name: String, commonDir: URL, worktrees: [Worktree] = []) {
        self.name = name
        self.commonDir = commonDir
        self.worktrees = worktrees
    }

    public var mainWorktree: Worktree? { worktrees.first(where: \.isMain) }
}
