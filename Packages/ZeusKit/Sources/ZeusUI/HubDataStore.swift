import Foundation
import Observation
import ZeusDomain

/// Drives the real Hub level (P3-C): runs the pure `HubDataLoader` and publishes the laid-out
/// `ConstellationHub` the view renders. Kept separate from `NavigationStore` (which owns only
/// navigation/zoom state) so neither becomes a god store. The ports are injected via the loader,
/// so the app wires concrete adapters while tests use stubs.
///
/// `HubDataLoader.load` is a nonisolated async function, so the scan + git reads run off the main
/// actor; only the `hub` publication resumes here on `@MainActor`.
///
/// Live refresh (P3-D.3c): when a `FileSystemWatching` adapter is injected, the store watches the
/// scan roots; each change is filtered through `ChangeRelevance` and debounced on an injected
/// clock before triggering a reconcile, so the constellation stays current — a new repo, a commit
/// (HEAD moves), a working-tree edit (status flips) — without the user relaunching.
@MainActor
@Observable
public final class HubDataStore {
    /// nil until the first load completes (the view shows a scanning state or sample fallback).
    public private(set) var hub: ConstellationHub?

    @ObservationIgnored private let loader: HubDataLoader
    @ObservationIgnored private let layout: ConstellationLayout
    @ObservationIgnored private var roots: [URL]
    @ObservationIgnored private let watcher: (any FileSystemWatching)?
    @ObservationIgnored private let relevance: ChangeRelevance
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    public init(loader: HubDataLoader,
                roots: [URL],
                layout: ConstellationLayout = ConstellationLayout(),
                watcher: (any FileSystemWatching)? = nil,
                relevance: ChangeRelevance = ChangeRelevance(),
                clock: any Clock<Duration> = ContinuousClock(),
                debounce: Duration = .milliseconds(300)) {
        self.loader = loader
        self.roots = roots
        self.layout = layout
        self.watcher = watcher
        self.relevance = relevance
        self.clock = clock
        self.debounce = debounce
    }

    deinit {
        watchTask?.cancel()
        refreshTask?.cancel()
    }

    /// Two-phase load (P3-D.2c): first paint the hub instantly from the persisted index, then
    /// reconcile against disk and republish. A failed reconcile keeps the cached paint if there
    /// is one; with nothing cached (e.g. first run / Full Disk Access denied) it publishes an
    /// empty hub — just the central star — so the scanning indicator clears instead of spinning.
    /// Finally arms the live-refresh watcher on the same roots.
    public func load() async {
        if let cached = await loader.cachedHub() {
            publish(cached)
        }
        do {
            publish(try await loader.rescan(roots: roots))
        } catch {
            if hub == nil { publish(.empty) }
        }
        startWatching(roots: roots)
    }

    /// Re-scans against `roots` and republishes — called when the user edits their scan roots in
    /// Settings (P3-D, Slice 2D). Unlike `load()` this skips the cached cold-start paint (the hub
    /// is already on screen), reconciles, and re-points the live-refresh watcher at the new roots.
    /// A failed rescan keeps the current hub: a transient scan error must not blank an already-
    /// painted constellation.
    public func reload(roots: [URL]) async {
        startWatching(roots: roots)
        await refresh()
    }

    /// (Re)starts the FSEvents subscription for `roots` (P3-D.3c) and adopts them as the roots a
    /// debounced refresh will rescan. Each path the watcher reports runs through `ChangeRelevance`
    /// (drops `node_modules`/build noise) and then re-arms the debounce, so a burst — an
    /// `npm install`, a branch switch touching many files — collapses to one reconcile. No-op
    /// beyond adopting the roots when no watcher was injected (previews / non-live tests).
    func startWatching(roots: [URL]) {
        self.roots = roots
        watchTask?.cancel()
        guard let watcher else { return }
        watchTask = Task { [weak self] in
            for await path in watcher.changes(under: roots) {
                self?.noteChange(at: path)
            }
        }
    }

    /// Handle one changed path: ignore build/dependency noise, else (re)arm the debounced refresh.
    /// Internal so the relevance + debounce behavior is unit-testable without driving the watcher.
    func noteChange(at path: String) {
        guard relevance.isRelevant(changedPath: path) else { return }
        scheduleRefresh()
    }

    /// Test seam: await the in-flight watch loop. Completes only when the watcher's stream is
    /// finite (a stub) — the production FSEvents stream runs until cancellation, so the app never
    /// awaits this.
    func waitForWatchLoop() async { await watchTask?.value }

    /// Test seam: await the in-flight debounced reconcile (no-op if none) — mirrors
    /// `NavigationStore.waitForTransition()` so tests drive the timed effect deterministically.
    public func waitForRefresh() async { await refreshTask?.value }

    /// Cancel any pending refresh and arm a fresh one: the debounce. Whichever change lands last
    /// within the window owns the single reconcile that fires.
    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self, clock, debounce] in
            try? await clock.sleep(for: debounce)
            guard let self, !Task.isCancelled else { return }
            await self.refresh()
        }
    }

    /// Reconcile against disk and republish, keeping the current hub if the rescan fails — a
    /// transient scan error must never blank an already-painted constellation.
    private func refresh() async {
        do { publish(try await loader.rescan(roots: roots)) }
        catch { /* keep the current hub */ }
    }

    private func publish(_ model: HubModel) {
        hub = layout.buildHub(clusters: model.clusters, hub: model.hub)
    }
}

private extension HubModel {
    /// Just the central star — the neutral hub shown when there's nothing to display yet. Built
    /// through `HubModelBuilder` (with no repos) so the empty hub can't drift from a populated one.
    static var empty: HubModel { HubModelBuilder().build(repos: []) }
}
