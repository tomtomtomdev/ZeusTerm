import Foundation
import Observation
import ZeusDomain

/// Drives the branch-tree Changes panel (slice 6, SPEC §7 View 3): when the user selects a commit,
/// it runs the pure `CommitDiffLoader` (off-main) for that sha and publishes the `CommitDiff` the
/// panel renders (changed files + unified diff). Owns one level's data like `CommitTreeStore` /
/// `WorktreeOrbitStore`, so no store becomes a god object.
///
/// `CommitDiffLoader.load` is a nonisolated async function, so the `git show` read runs off the main
/// actor; only the publication resumes here on `@MainActor`. Like the sibling stores, selecting a new
/// commit *supersedes* any in-flight load (cancellable single task + clear-on-start + cancel-guarded
/// publish) so a slower earlier diff can't clobber a newer selection.
@MainActor
@Observable
public final class CommitDiffStore {
    /// nil until the first commit's diff finishes loading and again while a new commit loads (so the
    /// panel never shows the previously-selected commit's stale diff).
    public private(set) var diff: CommitDiff?

    /// nil only for a fixture store (no git): then `load` publishes `fixtureDiff(sha)` instead.
    @ObservationIgnored private let loader: CommitDiffLoader?
    /// Per-sha diff source for a fixture store; nil for a real (loader-backed) store.
    @ObservationIgnored private let fixtureDiff: (@Sendable (String) -> CommitDiff)?
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    public init(loader: CommitDiffLoader) {
        self.loader = loader
        self.fixtureDiff = nil
    }

    /// Fixture seam (slice 7(b)): a store with no loader that resolves each selected commit's diff
    /// from `fixtureDiff` (the sample diffs) instead of `git show`, so the Changes panel swaps per
    /// selection in previews / `-uiTestFixtures` exactly as it does against real git.
    public init(fixtureDiff: @escaping @Sendable (String) -> CommitDiff) {
        self.loader = nil
        self.fixtureDiff = fixtureDiff
    }

    deinit { loadTask?.cancel() }

    /// Loads the diff for `sha` in the repo at `repoPath` and publishes it. Clears the previous
    /// commit's diff up front and cancels any in-flight load, so the panel reflects this selection
    /// and a slower earlier load can't clobber it. A failed read publishes an empty diff for `sha`
    /// (no files, empty patch) rather than leaving another commit's diff on screen.
    public func load(repoPath: URL, sha: String) {
        loadTask?.cancel()
        diff = nil
        guard let loader else {                       // fixture store: resolve the sample diff, no git
            loadTask = Task { [weak self] in
                guard let self, !Task.isCancelled else { return }   // a newer selection supersedes this
                self.diff = self.fixtureDiff?(sha)
            }
            return
        }
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await loader.load(repoPath: repoPath, sha: sha)
                if Task.isCancelled { return }
                self.diff = loaded
            } catch {
                if Task.isCancelled { return }
                self.diff = CommitDiff(sha: sha, files: [], patch: "")
            }
        }
    }

    /// Test seam: await the in-flight load (no-op if none), mirroring `CommitTreeStore.waitForLoad()`.
    public func waitForLoad() async { await loadTask?.value }
}
