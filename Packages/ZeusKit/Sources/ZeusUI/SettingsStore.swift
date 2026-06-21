import Foundation
import Observation
import ZeusDomain

/// UDF feature store behind the settings UI (P3-D roots, Slice 2C). Owns the editable
/// `ZeusSettings` and mutates the configured scan roots through explicit intents, persisting
/// every change through the injected `SettingsStoring` port. Kept separate from `HubDataStore`
/// (which owns hub data) and `NavigationStore` (zoom/navigation) so none becomes a god store.
///
/// The view binds to `scanRoots` and calls the intent methods; the composition root injects the
/// concrete SwiftData adapter, while tests inject an in-memory fake.
@MainActor
@Observable
public final class SettingsStore {
    public private(set) var settings: ZeusSettings

    @ObservationIgnored private let store: any SettingsStoring

    /// Loads persisted settings up front (a tiny singleton read). A failing load falls back to
    /// defaults rather than crashing — a corrupt/absent store must not block the app.
    public init(store: any SettingsStoring) {
        self.store = store
        self.settings = (try? store.load()) ?? ZeusSettings()
    }

    /// The user's configured discovery roots (path strings). Empty means "use the built-in dev
    /// roots" — `ScanRootResolver` applies that fallback when the scan actually runs.
    public var scanRoots: [String] { settings.scanRoots }

    public func addRoot(_ path: String) {
        guard !settings.scanRoots.contains(path) else { return }
        settings.scanRoots.append(path)
        persist()
    }

    public func removeRoot(_ path: String) {
        guard settings.scanRoots.contains(path) else { return }
        settings.scanRoots.removeAll { $0 == path }
        persist()
    }

    /// Clears every configured root, restoring the built-in default-roots behavior.
    public func resetRoots() {
        guard !settings.scanRoots.isEmpty else { return }
        settings.scanRoots.removeAll()
        persist()
    }

    private func persist() {
        try? store.save(settings)
    }
}
