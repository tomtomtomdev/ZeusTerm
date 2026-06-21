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

    /// `changedPaths` (P3-D.3 finding #2) are the paths FSEvents reported since the last scan. A
    /// known repo whose HEAD is unchanged but which has a changed path *under* it is rerouted from
    /// `reuse` to `refresh`, so a working-tree flip (clean↔dirty, no commit) re-reads its status
    /// instead of keeping the stale cached one. Empty (the default — `load`/`reload`/cold start) =
    /// the original HEAD-only bucketing.
    public func plan(cached: [IndexEntry], observed: [IndexEntry],
                     changedPaths: Set<String> = []) -> RescanPlan {
        // `cached` is path-unique (loaded from a path-keyed store); the closure is just a
        // defensive no-op should that ever loosen — last row wins, arbitrary but harmless here.
        let cachedByPath = Dictionary(cached.map { ($0.path, $0) }, uniquingKeysWith: { _, latest in latest })
        let observedPaths = Set(observed.map(\.path))

        var reuse: [IndexEntry] = []
        var refresh: [IndexEntry] = []
        for current in observed {
            // Reuse only a known repo whose HEAD is unchanged AND whose working tree is quiet
            // (no reported change under it). New/HEAD-moved repos, or a touched working tree, →
            // full re-read.
            if let prior = cachedByPath[current.path], prior.headSHA == current.headSHA,
               !changedPaths.contains(where: { isPath($0, under: current.path) }) {
                reuse.append(prior)
            } else {
                refresh.append(current)
            }
        }
        let remove = cached.filter { !observedPaths.contains($0.path) }
        return RescanPlan(reuse: reuse, refresh: refresh, remove: remove)
    }

    /// True when `changed` is the repo directory itself or a descendant of it. The trailing slash
    /// keeps a sibling like `/w/apple` from matching a repo at `/w/app`. Both sides are collapsed
    /// through the macOS `/private` firmlink first, because FSEvents reports temp roots as
    /// `/private/var/…` while the scanner's `url.path` says `/var/…` — without this they'd never
    /// match for a `/tmp`- or `/var`-rooted repo.
    private func isPath(_ changed: String, under repo: String) -> Bool {
        let changed = canonical(changed), repo = canonical(repo)
        return changed == repo || changed.hasPrefix(repo + "/")
    }

    /// Strips the macOS `/private` firmlink prefix so `/private/var/x` and `/var/x` (the same file)
    /// compare equal. Pure string work — no filesystem access — so the planner stays a pure decision.
    private func canonical(_ path: String) -> String {
        path.hasPrefix("/private/") ? String(path.dropFirst("/private".count)) : path
    }
}
