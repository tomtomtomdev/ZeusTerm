import Foundation

/// A node in the navigable Repo → Worktree → Branch → Commit display tree (feature #2).
public struct TreeNode: Identifiable, Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case repository, worktree, branch, commit
    }

    public let id: String
    public let kind: Kind
    public let title: String
    public var subtitle: String?
    public var badge: String?
    public var children: [TreeNode]

    public init(
        id: String,
        kind: Kind,
        title: String,
        subtitle: String? = nil,
        badge: String? = nil,
        children: [TreeNode] = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.badge = badge
        self.children = children
    }
}
