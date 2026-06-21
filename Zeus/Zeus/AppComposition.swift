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

    /// The Hub data store, seeded with the user's effective scan roots.
    @MainActor
    static func makeHubStore(settings: SettingsStore) -> HubDataStore {
        HubDataStore(
            loader: HubDataLoader(scanner: ProjectScanner(),
                                  git: GitCLIService(),
                                  index: makeIndexStore()),
            roots: effectiveRoots(for: settings))
    }

    /// The roots the scanner should walk: the user's configured roots when set, else the built-in
    /// dev roots — resolved in one place so the initial scan and every re-scan agree.
    @MainActor
    static func effectiveRoots(for settings: SettingsStore) -> [URL] {
        ScanRootResolver.effectiveRoots(configured: settings.scanRoots,
                                        defaults: ProjectScanner.defaultDevRoots())
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
