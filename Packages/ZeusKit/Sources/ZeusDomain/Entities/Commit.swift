import Foundation

/// A single git commit. `id` is the full SHA.
public struct Commit: Identifiable, Sendable, Hashable {
    public let id: String
    public var summary: String
    public var authorName: String
    public var date: Date

    public init(id: String, summary: String, authorName: String, date: Date) {
        self.id = id
        self.summary = summary
        self.authorName = authorName
        self.date = date
    }
}
