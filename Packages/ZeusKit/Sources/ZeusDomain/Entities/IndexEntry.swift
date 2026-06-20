import Foundation

/// One row of the persisted scan index (SPEC §188): a previously-discovered repo, keyed by its
/// filesystem `path` — the same stable identity used by `ClassifiedRepo.id`. `headSHA` lets the
/// incremental rescan detect whether the repo's HEAD moved since `lastScanned` without paying for
/// a full re-read; it's nil when HEAD is unreadable (e.g. a freshly `git init`'d repo, no commits).
public struct IndexEntry: Equatable, Sendable, Identifiable {
    public var id: String { path }
    public let path: String
    public let headSHA: String?
    public let lastScanned: Date

    public init(path: String, headSHA: String?, lastScanned: Date) {
        self.path = path
        self.headSHA = headSHA
        self.lastScanned = lastScanned
    }
}
