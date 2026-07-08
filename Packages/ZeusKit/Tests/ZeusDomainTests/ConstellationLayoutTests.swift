import Testing
import Foundation
@testable import ZeusDomain

struct ConstellationLayoutTests {

    // Mirrors the design's Backend cluster (5 members) + central monorepo hub.
    private func backendCluster() -> ClusterInput {
        ClusterInput(
            type: "Backend",
            center: StagePoint(x: 498, y: 118),
            spread: 82,
            members: [
                MemberInput(name: "tuntun-api", status: .dirty),
                MemberInput(name: "payments-svc", status: .clean),
                MemberInput(name: "auth-gateway", status: .ahead),
                MemberInput(name: "ledger-go", status: .clean),
                MemberInput(name: "notif-worker", status: .untracked),
            ])
    }

    private func hub() -> HubInput {
        HubInput(name: "tuntun-mono", center: StagePoint(x: 512, y: 252))
    }

    @Test func placesHubAndClusterMembersDeterministically() {
        let layout = ConstellationLayout()
        let result = layout.buildHub(clusters: [backendCluster()], hub: hub())

        // 1 hub star + 5 members
        #expect(result.stars.count == 6)

        let hubStar = try! #require(result.stars.first { $0.isHub })
        #expect(hubStar.point == StagePoint(x: 512, y: 252))
        #expect(hubStar.size == 16)
        #expect(hubStar.status == nil)

        let members = result.stars.filter { !$0.isHub }
        #expect(members.map(\.name) == ["tuntun-api", "payments-svc", "auth-gateway", "ledger-go", "notif-worker"])
        #expect(members.map(\.status) == [.dirty, .clean, .ahead, .clean, .untracked])

        // every member sits within the cluster's spread of its center
        for m in members {
            let dx = m.point.x - 498, dy = m.point.y - 118
            #expect((dx * dx + dy * dy).squareRoot() <= 82 * 1.02 + 0.001)
        }

        // deterministic: a second build is identical
        let again = layout.buildHub(clusters: [backendCluster()], hub: hub())
        #expect(again.stars == result.stars)
    }

    @Test func distinctMemberIdsSurviveDuplicateDisplayNames() {
        // Two repos named "api" in different folders must become two distinct stars —
        // StarNode.id keys off the stable member id (path), not the display name, so
        // SwiftUI ForEach doesn't collide.
        let cluster = ClusterInput(
            type: "Backend", center: StagePoint(x: 498, y: 118), spread: 82,
            members: [
                MemberInput(id: "/work/a/api", name: "api", status: .clean),
                MemberInput(id: "/work/b/api", name: "api", status: .dirty),
            ])
        let result = ConstellationLayout().buildHub(clusters: [cluster], hub: hub())

        let members = result.stars.filter { !$0.isHub }
        #expect(members.map(\.id) == ["/work/a/api", "/work/b/api"])
        #expect(members.map(\.name) == ["api", "api"])      // display name preserved
        #expect(Set(members.map(\.id)).count == 2)          // no id collision
    }

    @Test func connectsMembersInSequenceAndToHub() {
        let result = ConstellationLayout().buildHub(clusters: [backendCluster()], hub: hub())

        // 5 members → 4 consecutive edges + 1 edge from the first member to the hub
        #expect(result.edges.count == 5)
        #expect(result.edges.filter { $0.dim }.count == 1)      // the hub link is the dim one
        #expect(result.edges.filter { !$0.dim }.count == 4)

        // one uppercase-style cluster label per cluster, above the center
        #expect(result.labels.map(\.text) == ["Backend"])
        #expect(result.labels[0].point.y < 118)
    }
}
