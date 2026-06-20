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

    public init(scanner: any ProjectScanning,
                git: any GitReading,
                classifier: RepoClassifier = RepoClassifier(),
                builder: HubModelBuilder = HubModelBuilder()) {
        self.scanner = scanner
        self.git = git
        self.classifier = classifier
        self.builder = builder
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
}
