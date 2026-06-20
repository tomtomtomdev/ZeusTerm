import Foundation

/// Pure use case: groups classified repos into the hub level's `ClusterInput`s, placing each
/// type at its fixed stage slot (SPEC §7 / prototype geometry). Only non-empty types appear,
/// in canonical `RepoType` order; members are sorted by name so the layout is stable regardless
/// of scan order.
public struct HubModelBuilder: Sendable {
    private let hubName: String
    private let hubCenter: StagePoint

    public init(hubName: String = HubGeometry.hubName,
                hubCenter: StagePoint = HubGeometry.center) {
        self.hubName = hubName
        self.hubCenter = hubCenter
    }

    public func build(repos: [ClassifiedRepo]) -> HubModel {
        var byType: [RepoType: [ClassifiedRepo]] = [:]
        for repo in repos { byType[repo.type, default: []].append(repo) }

        // `allCases` is in declaration order → canonical cluster order; empty types drop out.
        let clusters = RepoType.allCases.compactMap { type -> ClusterInput? in
            guard let group = byType[type], !group.isEmpty else { return nil }
            let slot = HubGeometry.slot(for: type)
            let members = group
                .sorted { ($0.name, $0.id) < ($1.name, $1.id) }
                .map { MemberInput(id: $0.id, name: $0.name, status: $0.status) }
            return ClusterInput(type: type.displayName, center: slot.center,
                                spread: slot.spread, members: members)
        }
        return HubModel(clusters: clusters, hub: HubInput(name: hubName, center: hubCenter))
    }
}
