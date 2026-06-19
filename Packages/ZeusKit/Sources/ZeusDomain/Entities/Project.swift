import Foundation

/// A discovered coding project on disk, wrapping its git repository.
public struct Project: Identifiable, Sendable, Hashable {
    public let id: UUID
    public var name: String
    public var rootURL: URL
    public var repository: Repository

    public init(id: UUID, name: String, rootURL: URL, repository: Repository) {
        self.id = id
        self.name = name
        self.rootURL = rootURL
        self.repository = repository
    }
}
