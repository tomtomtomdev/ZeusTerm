import Foundation

/// A discovered repo after classification + git-status read — the input to the hub level.
public struct ClassifiedRepo: Sendable, Hashable {
    /// Stable identity (the repo's filesystem path for real scans), distinct from the
    /// display `name` so duplicate folder names stay separate stars on the hub.
    public var id: String
    public var name: String
    public var type: RepoType
    public var status: GitStatus
    /// `id` defaults to `name` for tests/fixtures where names are already unique.
    public init(id: String? = nil, name: String, type: RepoType, status: GitStatus) {
        self.id = id ?? name; self.name = name; self.type = type; self.status = status
    }
}

/// The hub level's inputs: one `ClusterInput` per non-empty type + the central hub.
/// Feed straight into `ConstellationLayout.buildHub(clusters:hub:)`.
public struct HubModel: Sendable, Hashable {
    public var clusters: [ClusterInput]
    public var hub: HubInput
    public init(clusters: [ClusterInput], hub: HubInput) {
        self.clusters = clusters; self.hub = hub
    }
}
