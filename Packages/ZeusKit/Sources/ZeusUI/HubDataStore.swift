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

    /// True when live refresh is configured on a TCC-protected root but the app lacks Full Disk
    /// Access, so FSEvents never fires (P3-D, FDA hint). Drives a dismissible banner nudging the
    /// user to grant access; the scan itself still works, only live updates are affected.
    public private(set) var liveRefreshNeedsFullDiskAccess = false

    @ObservationIgnored private let loader: HubDataLoader
    @ObservationIgnored private let layout: ConstellationLayout
    @ObservationIgnored private var roots: [URL]
    @ObservationIgnored private let watcher: (any FileSystemWatching)?
    @ObservationIgnored private let relevance: ChangeRelevance
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let fullDiskAccess: (any FullDiskAccessChecking)?
    @ObservationIgnored private let home: URL
    @ObservationIgnored private var fdaHintDismissed = false
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    /// Relevant paths reported by the watcher since the last reconcile, drained into the rescan so a
    /// HEAD-unchanged repo with a touched working tree re-reads its status (P3-D.3 finding #2).
    @ObservationIgnored private var pendingChangedPaths: Set<String> = []

    public init(loader: HubDataLoader,
                roots: [URL],
                layout: ConstellationLayout = ConstellationLayout(),
                watcher: (any FileSystemWatching)? = nil,
                relevance: ChangeRelevance = ChangeRelevance(),
                clock: any Clock<Duration> = ContinuousClock(),
                debounce: Duration = .milliseconds(300),
                fullDiskAccess: (any FullDiskAccessChecking)? = nil,
                home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.loader = loader
        self.roots = roots
        self.layout = layout
        self.watcher = watcher
        self.relevance = relevance
        self.clock = clock
        self.debounce = debounce
        self.fullDiskAccess = fullDiskAccess
        self.home = home
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
        await updateFullDiskAccessHint(roots: roots)
    }

    /// Re-scans against `roots` and republishes — called when the user edits their scan roots in
    /// Settings (P3-D, Slice 2D). Unlike `load()` this skips the cached cold-start paint (the hub
    /// is already on screen), reconciles, and re-points the live-refresh watcher at the new roots.
    /// A failed rescan keeps the current hub: a transient scan error must not blank an already-
    /// painted constellation.
    public func reload(roots: [URL]) async {
        startWatching(roots: roots)
        await refresh()
        await updateFullDiskAccessHint(roots: roots)
    }

    /// Recompute whether to nudge the user toward Full Disk Access for live refresh (P3-D, FDA hint).
    /// The probe reads a file, so it runs off the main actor; the pure `FullDiskAccessHint` rule then
    /// decides. No-op when no checker is injected (previews / non-live tests) or the user already
    /// dismissed the hint this session.
    private func updateFullDiskAccessHint(roots: [URL]) async {
        guard !fdaHintDismissed, let fullDiskAccess else { return }
        let hasAccess = await Task.detached { fullDiskAccess.hasFullDiskAccess() }.value
        liveRefreshNeedsFullDiskAccess = FullDiskAccessHint.isNeeded(
            hasAccess: hasAccess, roots: roots, home: home)
    }

    /// Re-probe Full Disk Access and recompute the hint — call when the app returns to the foreground,
    /// since the user may have just granted access in System Settings. Full Disk Access takes effect
    /// for the running process without a relaunch, but the launch-time probe result would otherwise
    /// stick and leave the banner up; this re-reads access against the roots last watched.
    public func recheckFullDiskAccessHint() async {
        await updateFullDiskAccessHint(roots: roots)
    }

    /// Hide the Full Disk Access hint for the rest of the session. It reappears on the next launch if
    /// access is still missing — a deliberate, gentle nudge rather than a one-time dialog.
    public func dismissFullDiskAccessHint() {
        fdaHintDismissed = true
        liveRefreshNeedsFullDiskAccess = false
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
        pendingChangedPaths.insert(path)
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
    /// transient scan error must never blank an already-painted constellation. Drains the changed
    /// paths accumulated since the last reconcile so a HEAD-unchanged repo with a touched working
    /// tree re-reads its status (P3-D.3 finding #2); they're cleared up front so a change arriving
    /// mid-rescan accumulates afresh and arms the next debounce rather than being lost.
    private func refresh() async {
        let changed = pendingChangedPaths
        pendingChangedPaths = []
        do { publish(try await loader.rescan(roots: roots, changedPaths: changed)) }
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
