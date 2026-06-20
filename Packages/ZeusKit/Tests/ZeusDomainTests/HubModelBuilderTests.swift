import Testing
@testable import ZeusDomain

/// P3-A: turning classified, status-read repos into the hub level's inputs — one `ClusterInput`
/// per non-empty `RepoType` at its fixed stage slot, plus the central `HubInput`. The output
/// feeds the existing pure `ConstellationLayout.buildHub`, so real repos render like the sample.
struct HubModelBuilderTests {

    @Test func emptyReposProduceJustTheHub() {
        let model = HubModelBuilder().build(repos: [])
        #expect(model.clusters.isEmpty)
        #expect(model.hub.name == "All Projects")
        #expect(model.hub.center == StagePoint(x: 512, y: 252))
    }

    @Test func oneRepoBecomesOneClusterAtItsTypeSlot() {
        let model = HubModelBuilder().build(
            repos: [ClassifiedRepo(name: "web", type: .frontend, status: .dirty)])

        #expect(model.clusters.count == 1)
        let cluster = try! #require(model.clusters.first)
        #expect(cluster.type == "Frontend")
        #expect(cluster.center == StagePoint(x: 205, y: 148))
        #expect(cluster.spread == 70)
        #expect(cluster.members == [MemberInput(name: "web", status: .dirty)])
    }

    @Test func clustersAppearInCanonicalTypeOrderAndEmptyTypesAreOmitted() {
        let model = HubModelBuilder().build(repos: [
            ClassifiedRepo(name: "api", type: .backend, status: .clean),
            ClassifiedRepo(name: "web", type: .frontend, status: .ahead),
            ClassifiedRepo(name: "bin", type: .scripts, status: .clean),
        ])
        // Canonical order is frontend < backend < ios < macos < mobile < scripts; iOS/macOS/
        // mobile have no repos so they're dropped.
        #expect(model.clusters.map(\.type) == ["Frontend", "Backend", "Scripts"])
    }

    @Test func membersWithinAClusterAreSortedByNameForStability() {
        let model = HubModelBuilder().build(repos: [
            ClassifiedRepo(name: "zebra", type: .frontend, status: .clean),
            ClassifiedRepo(name: "alpha", type: .frontend, status: .dirty),
        ])
        #expect(model.clusters[0].members.map(\.name) == ["alpha", "zebra"])
    }

    @Test func duplicateRepoNamesKeepDistinctMemberIdentities() {
        // Real scans can surface two repos with the same folder name at different paths;
        // their stable ids (paths) must flow through to the members so the hub renders both.
        let model = HubModelBuilder().build(repos: [
            ClassifiedRepo(id: "/work/a/api", name: "api", type: .backend, status: .clean),
            ClassifiedRepo(id: "/work/b/api", name: "api", type: .backend, status: .dirty),
        ])
        let members = model.clusters[0].members
        #expect(members.count == 2)
        #expect(Set(members.map(\.id)).count == 2)              // distinct identities
        #expect(members.allSatisfy { $0.name == "api" })        // same display name
    }

    @Test func otherTypeGetsItsOwnCluster() {
        let model = HubModelBuilder().build(
            repos: [ClassifiedRepo(name: "junk", type: .other, status: .clean)])
        #expect(model.clusters.map(\.type) == ["Other"])
    }

    @Test func outputFeedsConstellationLayout() {
        let model = HubModelBuilder().build(
            repos: [ClassifiedRepo(name: "web", type: .frontend, status: .dirty)])
        let hub = ConstellationLayout().buildHub(clusters: model.clusters, hub: model.hub)

        #expect(hub.stars.contains { $0.isHub && $0.name == "All Projects" })
        #expect(hub.stars.contains { $0.name == "web" && $0.status == .dirty && !$0.isHub })
    }
}
