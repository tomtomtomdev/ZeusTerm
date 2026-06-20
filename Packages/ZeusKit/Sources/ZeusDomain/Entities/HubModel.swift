import Foundation

/// A discovered repo after classification + git-status read — the input to the hub level.
public struct ClassifiedRepo: Sendable, Hashable {
    public var name: String
    public var type: RepoType
    public var status: GitStatus
    public init(name: String, type: RepoType, status: GitStatus) {
        self.name = name; self.type = type; self.status = status
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
