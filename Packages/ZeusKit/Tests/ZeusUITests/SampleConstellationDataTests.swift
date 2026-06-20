import Testing
import ZeusDomain
@testable import ZeusUI

/// `SampleConstellationData` mirrors the design prototype's seeded fixtures so the whole
/// constellation renders before the P3 scanner exists. These assert the laid-out levels
/// produced by feeding the fixtures through the pure ZeusDomain layout use cases.
struct SampleConstellationDataTests {
    private func node(_ sha: String, in tree: ConstellationTree) -> CommitNode {
        tree.nodes.first { $0.id == sha }!
    }

    @Test func hubHasMonorepoHubPlusClusterMembers() {
        let hub = SampleConstellationData.hub
        #expect(hub.stars.count == 24)                       // 1 hub + 23 cluster members
        #expect(hub.stars.filter { $0.isHub }.count == 1)
        #expect(hub.stars.first?.isHub == true)
        #expect(hub.stars.first?.name == "tuntun-mono")
        #expect(hub.labels.count == 6)                        // one floating label per cluster type
        #expect(hub.stars.contains { $0.name == "ZeusTerm" && $0.status == .dirty })
    }

    @Test func orbitsHaveTenSatellitesAcrossThreeRings() {
        let orbits = SampleConstellationData.orbits
        #expect(orbits.rings.count == 3)
        #expect(orbits.satellites.count == 10)
        let cache = orbits.satellites.first { $0.branch == "fix/cache-ttl" }
        #expect(cache?.status == .behind)
        #expect(orbits.satellites.contains { $0.branch == "feature/oauth-pkce" })
    }

    @Test func treeHasThirteenCommitsHeadAtTipNewestOnTop() {
        let tree = SampleConstellationData.tree
        #expect(tree.nodes.count == 13)
        #expect(tree.edges.count == 14)                       // one per present parent

        let head = tree.nodes.first { $0.isHead }
        #expect(head?.id == SampleConstellationData.headSHA)
        #expect(head?.id == "12ab9c")

        // HEAD is the branch tip → no commit is newer → nothing dimmed.
        #expect(tree.nodes.allSatisfy { !$0.isDim })

        // Time flows top→bottom: newest (HEAD) has the smallest y, oldest the largest.
        let newest = tree.nodes.min { $0.point.y < $1.point.y }
        let oldest = tree.nodes.max { $0.point.y < $1.point.y }
        #expect(newest?.id == "12ab9c")
        #expect(oldest?.id == "a1f3c9")
    }

    @Test func commitParentsDriveTopologicalRank() {
        let tree = SampleConstellationData.tree
        #expect(node("a1f3c9", in: tree).rank == 0)                              // init monorepo = root
        #expect(node("12ab9c", in: tree).rank > node("aa55fe", in: tree).rank)   // child ranks above parent
        // The merge commit ranks above BOTH merged parents.
        #expect(node("aa55fe", in: tree).rank > node("90ab33", in: tree).rank)
        #expect(node("aa55fe", in: tree).rank > node("81c3e0", in: tree).rank)
    }

    @Test func exposesProjectAndTipDefaults() {
        #expect(SampleConstellationData.projectName == "tuntun-api")
        #expect(SampleConstellationData.headSHA == "12ab9c")
        #expect(SampleConstellationData.lanes["develop"] == 580)
    }
}
