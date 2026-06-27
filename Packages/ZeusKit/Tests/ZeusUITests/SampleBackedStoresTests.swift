import Testing
import Foundation
import ZeusDomain
@testable import ZeusUI

/// Slice 7(b): the `ConstellationShell` no longer reaches for `SampleConstellationData` itself.
/// Instead the composition roots (previews / ZoomSpike / `-uiTestFixtures`) inject *fixture-backed*
/// stores seeded from the sample, and the shell keeps only a neutral empty fallback. These pin the
/// fixture-store seams the shell relies on: a fixture store renders the seeded level verbatim and
/// ignores the navigation-driven git loads (no scan / git CLI / Full Disk Access), so previews and
/// XCUITests stay deterministic and host-independent.
@MainActor
struct SampleBackedStoresTests {

    /// The hub fixture paints the seeded hub up front and the shell's on-appear `load()` keeps it —
    /// no scan runs, so it can't blank the constellation or raise the Full Disk Access hint.
    @Test func fixtureHubStoreRendersTheSeededHubAndNeverScans() async {
        let store = HubDataStore(fixtureHub: SampleConstellationData.hub)
        #expect(store.hub == SampleConstellationData.hub)

        await store.load()                                   // shell calls this on appear
        #expect(store.hub == SampleConstellationData.hub)    // kept — no real scan clobbered it
        #expect(store.liveRefreshNeedsFullDiskAccess == false)
    }

    /// Diving into any repo must not replace the seeded sample orbits with a real git read.
    @Test func fixtureOrbitStoreKeepsTheSeededOrbitsAcrossADive() async {
        let store = WorktreeOrbitStore(fixtureOrbits: SampleConstellationData.orbits)
        #expect(store.orbits == SampleConstellationData.orbits)

        store.load(repoPath: URL(fileURLWithPath: "/anything"))   // shell dives into a repo
        await store.waitForLoad()
        #expect(store.orbits == SampleConstellationData.orbits)    // verbatim, navigation-agnostic
    }

    /// The tree fixture publishes its tip asynchronously on load so the shell's `.onChange(tip)`
    /// fires `.branchTipResolved`, landing HEAD/selected on the tip exactly like the real store.
    @Test func fixtureTreeStorePublishesTheSeededTreeAndTipOnLoad() async {
        let store = CommitTreeStore(fixtureTree: SampleConstellationData.tree,
                                    fixtureTip: SampleConstellationData.tipSHA)

        store.load(repoPath: URL(fileURLWithPath: "/anything"), branch: "develop")
        await store.waitForLoad()
        #expect(store.tree == SampleConstellationData.tree)
        #expect(store.tip == SampleConstellationData.tipSHA)       // drives .branchTipResolved
    }

    /// Selecting a commit must show that commit's sample diff, and selecting another must swap it —
    /// the slice-6 behavior the XCUITest exercises, driven here off the sample diffs.
    @Test func fixtureDiffStoreReturnsTheSelectedCommitsSampleDiff() async {
        let store = CommitDiffStore(fixtureDiff: SampleConstellationData.diff(forSHA:))

        store.load(repoPath: URL(fileURLWithPath: "/anything"), sha: "12ab9c")
        await store.waitForLoad()
        #expect(store.diff == SampleConstellationData.diff(forSHA: "12ab9c"))

        store.load(repoPath: URL(fileURLWithPath: "/anything"), sha: "aa55fe")
        await store.waitForLoad()
        #expect(store.diff == SampleConstellationData.diff(forSHA: "aa55fe"))   // swaps per selection
    }
}
