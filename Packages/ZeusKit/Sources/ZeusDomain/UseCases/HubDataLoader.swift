import Foundation

/// Pure orchestration use case (P3-C): turns scan roots into a `HubModel` by wiring the
/// `ProjectScanning` + `GitReading` ports through `RepoClassifier` + `HubModelBuilder`. The
/// I/O lives in the injected adapters; this just sequences them, so it's unit-testable with
/// stub ports. Output feeds `ConstellationLayout.buildHub` exactly like the sample fixtures.
public struct HubDataLoader: Sendable {
    private let scanner: any ProjectScanning
    private let git: any GitReading
    private let classifier: RepoClassifier
    private let builder: HubModelBuilder
    /// Optional persisted index (P3-D.2c). When present, cold start paints `cachedHub()` from it
    /// before `rescan(roots:)` reconciles; absent, the loader just does a full `load(roots:)`.
    private let index: (any RepositoryIndexStore)?
    /// Timestamp source for `IndexEntry.lastScanned` (injected so tests are deterministic). This is
    /// a clock for *stamping*, not for *delaying* — unlike `NavigationStore`'s `Clock<Duration>`,
    /// which it needs to sleep through zoom transitions — so the simpler `() -> Date` is the fit.
    private let now: @Sendable () -> Date

    public init(scanner: any ProjectScanning,
                git: any GitReading,
                classifier: RepoClassifier = RepoClassifier(),
                builder: HubModelBuilder = HubModelBuilder(),
                index: (any RepositoryIndexStore)? = nil,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.scanner = scanner
        self.git = git
        self.classifier = classifier
        self.builder = builder
        self.index = index
        self.now = now
    }

    /// Cold-start paint (P3-D.2c): builds the fully typed + colored hub straight from the persisted
    /// index — no disk scan, no git reads — so the constellation appears instantly while
    /// `rescan(roots:)` reconciles in the background. Returns nil when there's no index or it's
    /// empty (first ever run), so the caller falls through to a scanning state. A failed index read
    /// is swallowed (treated as no cache) rather than blocking the first paint.
    public func cachedHub() async -> HubModel? {
        guard let index, let cached = try? await index.load(), !cached.isEmpty else { return nil }
        return builder.build(repos: cached.map(classifiedRepo(from:)))
    }

    /// Incremental reconcile (P3-D.2c): discovers repos, compares each one's current HEAD against
    /// the index, and re-reads (classify + status) ONLY the new or HEAD-moved repos — unchanged
    /// repos keep their cached rich payload untouched. Persists the delta (upsert the refreshed
    /// rows, drop the vanished ones) and returns the reconciled hub. Runs in the background after
    /// `cachedHub()` has already painted, so the expensive reads never block first render.
    ///
    /// Failure contract: only `scanner.discoverRepositoryURLs` propagates — without the repo list
    /// there's nothing to reconcile. Everything else degrades gracefully: a failed index *read*
    /// falls back to an empty cache (so every repo looks new — a correct, if non-incremental,
    /// full rescan); per-repo HEAD/classify/status failures are isolated; and the index *writes*
    /// are best-effort, so a transient persistence error never blanks an already-correct hub.
    public func rescan(roots: [URL]) async throws -> HubModel {
        let urls = try await scanner.discoverRepositoryURLs(under: roots)

        var cached: [IndexEntry] = []
        if let index { cached = (try? await index.load()) ?? [] }

        // Cheap HEAD read per repo → the planner buckets reuse/refresh/remove on path + HEAD.
        // A thrown HEAD read collapses to nil here: the repo is still reconciled, but a transient
        // failure that flips a real sha→nil forces one extra refresh on the next clean scan.
        var observed: [IndexEntry] = []
        observed.reserveCapacity(urls.count)
        for url in urls {
            let head: String? = (try? await git.headSHA(at: url)) ?? nil
            observed.append(IndexEntry(path: url.path, headSHA: head, lastScanned: now()))
        }
        let plan = IncrementalRescanPlanner().plan(cached: cached, observed: observed)

        // The expensive part, paid only for what changed; reuse rows already carry type+status.
        var refreshed: [IndexEntry] = []
        refreshed.reserveCapacity(plan.refresh.count)
        for entry in plan.refresh {
            let repo = await classify(URL(fileURLWithPath: entry.path))
            refreshed.append(IndexEntry(path: entry.path, headSHA: entry.headSHA,
                                        type: repo.type, status: repo.status, lastScanned: now()))
        }

        // Build the result first, then persist best-effort: a write failure leaves the index stale
        // (next rescan retries) but must not discard a fully-computed reconcile.
        let hub = builder.build(repos: (plan.reuse + refreshed).map(classifiedRepo(from:)))
        if let index {
            try? await index.upsert(refreshed)
            try? await index.remove(paths: plan.remove.map(\.path))
        }
        return hub
    }

    public func load(roots: [URL]) async throws -> HubModel {
        let urls = try await scanner.discoverRepositoryURLs(under: roots)
        // Per-repo reads are sequential for now. Bounded-concurrency parallelism (and
        // caching) is deferred to P3-D against the §4 S5 perf spike — an unbounded TaskGroup
        // would spawn one `git` process per repo, which can be slower than it looks.
        var repos: [ClassifiedRepo] = []
        repos.reserveCapacity(urls.count)
        for url in urls {
            repos.append(await classify(url))
        }
        return builder.build(repos: repos)
    }

    /// Classifies + reads status for one repo. Per-repo reads are resilient: an unreadable
    /// root classifies as `.other`, and a failed status read falls back to `.clean` (neutral)
    /// so a single bad repo never aborts the whole scan. The repo path is the stable id.
    private func classify(_ url: URL) async -> ClassifiedRepo {
        let entries = (try? scanner.rootEntryNames(at: url)) ?? []
        let type = classifier.classify(rootEntries: entries, name: url.lastPathComponent)
        let status = (try? await git.status(at: url)) ?? .clean
        return ClassifiedRepo(id: url.path, name: url.lastPathComponent, type: type, status: status)
    }

    /// Projects a persisted index row back into a hub member. The path is both the stable id and
    /// the source of the display name; type/status come straight from the cached rich payload.
    private func classifiedRepo(from entry: IndexEntry) -> ClassifiedRepo {
        ClassifiedRepo(id: entry.path,
                       name: URL(fileURLWithPath: entry.path).lastPathComponent,
                       type: entry.type,
                       status: entry.status)
    }
}
