import Foundation
import Observation
import ZeusDomain

/// Drives the worktree (orbit) level: when the user dives into a repo, it runs the pure
/// `WorktreeOrbitLoader` (off-main) for that repo's path and publishes the laid-out
/// `ConstellationOrbits` the view renders. Kept separate from `NavigationStore` (navigation/zoom)
/// and `HubDataStore` (the hub) so no store becomes a god object — each owns one level's data.
///
/// `WorktreeOrbitLoader.load` is a nonisolated async function, so `readRepository` + the per-worktree
/// status reads run off the main actor; only the `orbits` publication resumes here on `@MainActor`.
///
/// Like `HubDataStore`, a new dive *supersedes* any in-flight load: the prior load's task is
/// cancelled and its result discarded, so the orbit level always reflects the latest dived-into
/// repo even when an earlier repo's git reads finish later (last-requested wins, not last-to-finish).
@MainActor
@Observable
public final class WorktreeOrbitStore {
    /// The canonical orbit-level center in stage space (matches the design prototype). The repo
    /// star sits here and its worktree satellites orbit it. `nonisolated` so the (nonisolated)
    /// sample fixture can reference this single source of truth instead of re-hardcoding the point.
    nonisolated public static let defaultCenter = StagePoint(x: 512, y: 256)

    /// nil until the first repo finishes loading and again while a new repo loads (so the view
    /// shows just the central star, never the previous repo's stale satellites).
    public private(set) var orbits: ConstellationOrbits?

    @ObservationIgnored private let loader: WorktreeOrbitLoader
    @ObservationIgnored private let layout: ConstellationLayout
    @ObservationIgnored private let ringPlanner: OrbitRingPlanner
    @ObservationIgnored private let center: StagePoint
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    public init(loader: WorktreeOrbitLoader,
                layout: ConstellationLayout = ConstellationLayout(),
                ringPlanner: OrbitRingPlanner = OrbitRingPlanner(),
                center: StagePoint = WorktreeOrbitStore.defaultCenter) {
        self.loader = loader
        self.layout = layout
        self.ringPlanner = ringPlanner
        self.center = center
    }

    deinit { loadTask?.cancel() }

    /// Loads the worktrees for the repo at `repoPath` and publishes the laid-out orbits. Clears the
    /// previous repo's orbits up front and cancels any in-flight load, so the level reflects this
    /// dive and a slower earlier load can't clobber it. A failed repository read publishes just the
    /// central star (no satellites) rather than leaving another repo's orbits on screen.
    public func load(repoPath: URL) {
        loadTask?.cancel()
        orbits = nil
        let name = repoPath.lastPathComponent
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let worktrees = try await self.loader.load(repoPath: repoPath)
                if Task.isCancelled { return }
                self.publish(name: name, worktrees: worktrees)
            } catch {
                if Task.isCancelled { return }
                self.orbits = .empty(center: self.center, name: name)
            }
        }
    }

    /// Test seam: await the in-flight load (no-op if none), mirroring `HubDataStore.waitForRefresh()`
    /// so tests drive the async load deterministically.
    public func waitForLoad() async { await loadTask?.value }

    private func publish(name: String, worktrees: [WorktreeInput]) {
        orbits = layout.buildOrbits(center: center, name: name,
                                    worktrees: worktrees,
                                    rings: ringPlanner.rings(forWorktreeCount: worktrees.count))
    }
}
