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

    /// Scans + classifies the roots and lays out the hub. A failed scan (e.g. Full Disk Access
    /// denied on first run) publishes an empty hub — just the central star — so the view's
    /// scanning indicator clears instead of spinning forever.
    public func load() async {
        do {
            let model = try await loader.load(roots: roots)
            hub = layout.buildHub(clusters: model.clusters, hub: model.hub)
        } catch {
            hub = layout.buildHub(clusters: [], hub: HubInput(name: HubGeometry.hubName,
                                                              center: HubGeometry.center))
        }
    }
}
