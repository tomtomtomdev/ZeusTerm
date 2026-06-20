import Foundation

/// Pure use case: groups classified repos into the hub level's `ClusterInput`s, placing each
/// type at its fixed stage slot (SPEC §7 / prototype geometry). Only non-empty types appear,
/// in canonical `RepoType` order; members are sorted by name so the layout is stable regardless
/// of scan order.
public struct HubModelBuilder: Sendable {
    private let hubName: String
    private let hubCenter: StagePoint

    public init(hubName: String = "All Projects",
                hubCenter: StagePoint = StagePoint(x: 512, y: 252)) {
        self.hubName = hubName
        self.hubCenter = hubCenter
    }

    public func build(repos: [ClassifiedRepo]) -> HubModel {
        var byType: [RepoType: [ClassifiedRepo]] = [:]
        for repo in repos { byType[repo.type, default: []].append(repo) }

        // `allCases` is in declaration order → canonical cluster order; empty types drop out.
        let clusters = RepoType.allCases.compactMap { type -> ClusterInput? in
            guard let group = byType[type], !group.isEmpty else { return nil }
            let slot = Self.slot(for: type)
            let members = group
                .sorted { ($0.name, $0.id) < ($1.name, $1.id) }
                .map { MemberInput(id: $0.id, name: $0.name, status: $0.status) }
            return ClusterInput(type: type.displayName, center: slot.center,
                                spread: slot.spread, members: members)
        }
        return HubModel(clusters: clusters, hub: HubInput(name: hubName, center: hubCenter))
    }

    /// Fixed stage-space slot per type (SPEC §7 / prototype geometry); `other` fills the
    /// bottom-center gap below the hub.
    private static func slot(for type: RepoType) -> (center: StagePoint, spread: Double) {
        switch type {
        case .frontend: (StagePoint(x: 205, y: 148), 70)
        case .backend:  (StagePoint(x: 498, y: 118), 82)
        case .ios:      (StagePoint(x: 788, y: 158), 56)
        case .macos:    (StagePoint(x: 862, y: 342), 52)
        case .mobile:   (StagePoint(x: 608, y: 408), 58)
        case .scripts:  (StagePoint(x: 218, y: 392), 64)
        case .other:    (StagePoint(x: 430, y: 472), 60)
        }
    }
}
