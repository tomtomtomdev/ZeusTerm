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
@MainActor
@Observable
public final class HubDataStore {
    /// nil until the first load completes (the view shows a scanning state or sample fallback).
    public private(set) var hub: ConstellationHub?

    @ObservationIgnored private let loader: HubDataLoader
    @ObservationIgnored private let layout: ConstellationLayout
    @ObservationIgnored private let roots: [URL]

    public init(loader: HubDataLoader,
                roots: [URL],
                layout: ConstellationLayout = ConstellationLayout()) {
        self.loader = loader
        self.roots = roots
        self.layout = layout
    }

    /// Two-phase load (P3-D.2c): first paint the hub instantly from the persisted index, then
    /// reconcile against disk and republish. A failed reconcile keeps the cached paint if there
    /// is one; with nothing cached (e.g. first run / Full Disk Access denied) it publishes an
    /// empty hub — just the central star — so the scanning indicator clears instead of spinning.
    public func load() async {
        if let cached = await loader.cachedHub() {
            publish(cached)
        }
        do {
            publish(try await loader.rescan(roots: roots))
        } catch {
            if hub == nil { publish(.empty) }
        }
    }

    private func publish(_ model: HubModel) {
        hub = layout.buildHub(clusters: model.clusters, hub: model.hub)
    }
}

private extension HubModel {
    /// Just the central star — the neutral hub shown when there's nothing to display yet.
    static var empty: HubModel {
        HubModel(clusters: [], hub: HubInput(name: HubGeometry.hubName, center: HubGeometry.center))
    }
}
