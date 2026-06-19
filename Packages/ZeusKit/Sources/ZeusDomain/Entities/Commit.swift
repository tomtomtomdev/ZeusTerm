import Foundation

/// A single git commit. `id` is the full SHA. `parents` are parent SHAs (for graph edges).
public struct Commit: Identifiable, Sendable, Hashable {
    public let id: String
    public var summary: String
    public var authorName: String
    public var date: Date
    public var parents: [String]

    public init(id: String, summary: String, authorName: String, date: Date,
                parents: [String] = []) {
        self.id = id
        self.summary = summary
        self.authorName = authorName
        self.date = date
        self.parents = parents
    }
}
