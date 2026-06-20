import Foundation

/// One row of the persisted scan index (SPEC §188): a previously-discovered repo, keyed by its
/// filesystem `path` — the same stable identity used by `ClassifiedRepo.id`. `headSHA` lets the
/// incremental rescan detect whether the repo's HEAD moved since `lastScanned` without paying for
/// a full re-read; it's nil when HEAD is unreadable (e.g. a freshly `git init`'d repo, no commits).
///
/// `type` + `status` are the cached "rich" payload (P3-D.2c): persisting them lets cold start paint
/// the fully typed + colored hub straight from the index, before any rescan reads disk. They
/// default to the neutral `.other`/`.clean` so the planner and older fixtures can build index rows
/// that only care about path + HEAD without naming a type/status.
public struct IndexEntry: Equatable, Sendable, Identifiable {
    public var id: String { path }
    public let path: String
    public let headSHA: String?
    public let type: RepoType
    public let status: GitStatus
    public let lastScanned: Date

    public init(path: String,
                headSHA: String?,
                type: RepoType = .other,
                status: GitStatus = .clean,
                lastScanned: Date) {
        self.path = path
        self.headSHA = headSHA
        self.type = type
        self.status = status
        self.lastScanned = lastScanned
    }
}
