import Foundation

/// A git branch and the commits reachable from it (paginated in practice).
public struct Branch: Identifiable, Sendable, Hashable {
    public var id: String { name }
    public var name: String
    public var isCurrent: Bool
    public var upstream: String?
    public var ahead: Int
    public var behind: Int
    public var commits: [Commit]

    public init(
        name: String,
        isCurrent: Bool = false,
        upstream: String? = nil,
        ahead: Int = 0,
        behind: Int = 0,
        commits: [Commit] = []
    ) {
        self.name = name
        self.isCurrent = isCurrent
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
        self.commits = commits
    }
}
