//
//  AppComposition.swift
//  Zeus
//
//  The composition root's factory helpers (CLAUDE.md). Wires the concrete adapters
//  (ProjectScanner + GitCLIService + GRDB index + SwiftData settings) into the UI feature
//  stores. Kept out of ZeusApp/ContentView so both the main window and the Settings scene can
//  share the same SettingsStore instance, and the scan-roots resolution lives in one place.
//

import Foundation
import ZeusUI
import ZeusDomain
import ZeusScanner
import ZeusGit
import ZeusIndex
import ZeusSettingsStore
import ZeusSuggest

enum AppComposition {

    /// The persistent settings store, pinned under Application Support next to the scan index.
    /// Falls back to an in-memory store (then a trivial ephemeral one) so a failure to open the
    /// on-disk store degrades to "settings don't persist" rather than blocking launch.
    static func makeSettingsStore() -> any SettingsStoring {
        if let url = settingsStoreURL(), let store = try? SwiftDataSettingsStore(url: url) {
            return store
        }
        if let memory = try? SwiftDataSettingsStore(inMemory: true) { return memory }
        return EphemeralSettingsStore()
    }

    /// The Hub data store, seeded with the user's effective scan roots and an FSEvents watcher so
    /// the Hub stays live (P3-D.3): a new/removed repo, a commit, or a working-tree edit refreshes
    /// the constellation without a relaunch. `ChangeRelevance` is handed the *same* pruned-dir set
    /// the scanner walks with, so the two filters can't drift (e.g. an `npm install` under
    /// `node_modules` is ignored by both). A `FullDiskAccessProbe` lets the store nudge the user
    /// when live refresh is configured on a TCC-protected root but the app lacks Full Disk Access
    /// (FSEvents silently never fires there without it — P3-D, FDA hint).
    @MainActor
    static func makeHubStore(settings: SettingsStore) -> HubDataStore {
        HubDataStore(
            loader: HubDataLoader(scanner: ProjectScanner(),
                                  git: GitCLIService(),
                                  index: makeIndexStore()),
            roots: effectiveRoots(for: settings),
            watcher: FSEventsWatcher(),
            relevance: ChangeRelevance(prunedDirectoryNames: ProjectScanner.defaultPruned),
            fullDiskAccess: FullDiskAccessProbe(),
            protectedRootsWhenAccessGranted: protectedRootsWhenAccessGranted(for: settings))
    }

    /// The worktree (orbit) data store: loads a dived-into repo's real worktrees through the same
    /// `git` CLI adapter the rest of the app uses. Stateless beyond the loader, so unlike the Hub
    /// store it needs no roots/index/watcher — it loads on demand when the user dives into a repo.
    @MainActor
    static func makeOrbitStore() -> WorktreeOrbitStore {
        WorktreeOrbitStore(loader: WorktreeOrbitLoader(git: GitCLIService()))
    }

    /// The branch-tree data store: loads a dived-into worktree's branch commit history through the
    /// same `git` CLI adapter. Like the orbit store it's stateless beyond the loader and loads on
    /// demand when the user dives into a worktree.
    @MainActor
    static func makeTreeStore() -> CommitTreeStore {
        CommitTreeStore(loader: CommitTreeLoader(git: GitCLIService()))
    }

    /// The Changes-panel data store: loads a selected commit's changed files + unified diff through
    /// the same `git` CLI adapter. Stateless beyond the loader; loads on demand when the user selects
    /// a commit on the branch-tree level.
    @MainActor
    static func makeDiffStore() -> CommitDiffStore {
        CommitDiffStore(loader: CommitDiffLoader(git: GitCLIService()))
    }

    /// The autosuggestion store backing the app-managed command line (feature #4, P6). Seeds the
    /// frecency engine with the user's real zsh history (best-effort, read-only; degrades to empty
    /// if the file can't be read) so suggestions reflect what they actually run. Git-subcommand
    /// knowledge + cwd path completion layer on top. Depends only on the `SuggestionProviding`
    /// engine, which is injected here at the composition root.
    @MainActor
    static func makeSuggestionStore() -> SuggestionStore {
        let history = ShellHistoryReader().history(at: ShellHistoryReader.defaultHistoryURL())
        return SuggestionStore(engine: SuggestionEngine(history: history))
    }

    /// The roots the scanner should walk: the user's configured roots when set, else the built-in
    /// dev roots — resolved in one place so the initial scan and every re-scan agree. The defaults
    /// exclude TCC-protected folders (Desktop/Documents/Downloads) so a first scan pops no per-folder
    /// permission dialogs; they're folded in later only if the user grants Full Disk Access.
    @MainActor
    static func effectiveRoots(for settings: SettingsStore) -> [URL] {
        ScanRootResolver.effectiveRoots(configured: settings.scanRoots,
                                        defaults: ProjectScanner.defaultDevRoots())
    }

    /// The TCC-protected default roots that exist on disk but are held out of the initial scan — the
    /// store folds them in once Full Disk Access is granted (widen-on-grant). Empty when the user
    /// configured their own roots: their explicit list is authoritative, so nothing is auto-added.
    @MainActor
    static func protectedRootsWhenAccessGranted(for settings: SettingsStore) -> [URL] {
        guard settings.scanRoots.isEmpty else { return [] }
        let withProtected = Set(ProjectScanner.defaultDevRoots(includeProtected: true))
        let withoutProtected = Set(ProjectScanner.defaultDevRoots())
        return Array(withProtected.subtracting(withoutProtected))
    }

    // MARK: - Storage locations

    /// `~/Library/Application Support/Zeus`, created if needed; nil if the container is unwritable.
    private static func appSupportDirectory() -> URL? {
        let fileManager = FileManager.default
        guard let appSupport = try? fileManager.url(for: .applicationSupportDirectory,
                                                    in: .userDomainMask,
                                                    appropriateFor: nil,
                                                    create: true) else { return nil }
        let directory = appSupport.appendingPathComponent("Zeus", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func settingsStoreURL() -> URL? {
        appSupportDirectory()?.appendingPathComponent("settings.store")
    }

    /// Opens the persisted scan index; nil on failure so the loader cleanly falls back to a full
    /// live scan rather than blocking startup.
    private static func makeIndexStore() -> GRDBRepositoryIndexStore? {
        guard let directory = appSupportDirectory() else { return nil }
        let dbPath = directory.appendingPathComponent("index.sqlite").path
        return try? GRDBRepositoryIndexStore(path: dbPath)
    }
}

/// Non-persistent last-resort `SettingsStoring` so the app still runs if even the in-memory
/// SwiftData store can't be created. Edits live only for the session.
final class EphemeralSettingsStore: SettingsStoring, @unchecked Sendable {
    private var settings = ZeusSettings()
    func load() throws -> ZeusSettings { settings }
    func save(_ settings: ZeusSettings) throws { self.settings = settings }
}
