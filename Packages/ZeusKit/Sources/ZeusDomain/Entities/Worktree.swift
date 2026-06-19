import Foundation

/// A git worktree (the main checkout or a linked worktree) and its branches.
public struct Worktree: Identifiable, Sendable, Hashable {
    public var id: URL { path }
    public var path: URL
    public var isMain: Bool
    public var isLocked: Bool
    public var branches: [Branch]

    public init(
        path: URL,
        isMain: Bool,
        isLocked: Bool = false,
        branches: [Branch] = []
    ) {
        self.path = path
        self.isMain = isMain
        self.isLocked = isLocked
        self.branches = branches
    }

    /// The checked-out branch for this worktree, if any.
    public var currentBranch: Branch? { branches.first(where: \.isCurrent) }
}
