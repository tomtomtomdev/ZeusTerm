import Foundation

/// The outcome of reconciling the persisted index against a fresh scan. Each previously- or
/// newly-seen repo lands in exactly one bucket; the adapter (P3-D.2) acts on them: re-read the
/// `refresh` repos, keep the `reuse` ones as-is, and delete the `remove` ones from the index.
public struct RescanPlan: Equatable, Sendable {
    /// In the index and still present with an unchanged HEAD — no expensive re-read needed.
    public let reuse: [IndexEntry]
    /// New repos, or ones whose HEAD moved since last scan — need a full classify + status read.
    public let refresh: [IndexEntry]
    /// Indexed before but gone from disk now — drop them.
    public let remove: [IndexEntry]

    public init(reuse: [IndexEntry], refresh: [IndexEntry], remove: [IndexEntry]) {
        self.reuse = reuse
        self.refresh = refresh
        self.remove = remove
    }
}

/// P3-D.1 — pure incremental-rescan decision. Buckets repos by comparing the persisted index
/// (`cached`) against what a fresh scan observed (`observed` = discovered repos + current HEAD).
/// No git, no filesystem, no clock: the adapter does the cheap HEAD reads and persistence; this
/// just decides what changed, so it's fully unit-testable.
public struct IncrementalRescanPlanner: Sendable {
    public init() {}

    public func plan(cached: [IndexEntry], observed: [IndexEntry]) -> RescanPlan {
        // `cached` is path-unique (loaded from a path-keyed store); the closure is just a
        // defensive no-op should that ever loosen — last row wins, arbitrary but harmless here.
        let cachedByPath = Dictionary(cached.map { ($0.path, $0) }, uniquingKeysWith: { _, latest in latest })
        let observedPaths = Set(observed.map(\.path))

        var reuse: [IndexEntry] = []
        var refresh: [IndexEntry] = []
        for current in observed {
            // Unchanged HEAD on a known repo → keep the cached row untouched (no re-read).
            // New repo, or HEAD moved (including HEAD becoming readable), → full re-read.
            if let prior = cachedByPath[current.path], prior.headSHA == current.headSHA {
                reuse.append(prior)
            } else {
                refresh.append(current)
            }
        }
        let remove = cached.filter { !observedPaths.contains($0.path) }
        return RescanPlan(reuse: reuse, refresh: refresh, remove: remove)
    }
}
