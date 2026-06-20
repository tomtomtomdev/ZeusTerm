import Foundation
import Testing
@testable import ZeusDomain

/// P3-D.1 — the pure incremental-rescan decision. Given the previously-indexed repos
/// (`cached`, loaded from the `RepositoryIndexStore`) and what a fresh scan observed now
/// (`observed` = each discovered repo + its current HEAD sha), bucket every repo into:
///   • reuse   — present in both, HEAD unchanged → no expensive re-read needed
///   • refresh — new repo, or HEAD moved → needs a full classify + status read
///   • remove  — was indexed but is gone from disk → drop from the index/hub
/// Pure set reconciliation keyed on path — no git, no filesystem, no clock. The adapter
/// (P3-D.2) reads the cheap HEAD shas and persists the result; this just decides.
///
/// Test List:
///  [x] empty cache + empty scan            → empty plan
///  [x] observed repo absent from cache      → refresh (new)
///  [x] cached repo absent from scan         → remove (gone)
///  [x] in both, same HEAD                    → reuse
///  [x] in both, HEAD moved                   → refresh (changed)
///  [x] HEAD became readable (nil → sha)      → refresh
///  [x] mixed scenario covering all buckets at once
struct IncrementalRescanPlannerTests {

    // Fixed clock — bucketing ignores lastScanned, so a constant keeps the data evident.
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func entry(_ path: String, head: String?) -> IndexEntry {
        IndexEntry(path: path, headSHA: head, lastScanned: t0)
    }

    @Test func emptyStateProducesEmptyPlan() {
        let plan = IncrementalRescanPlanner().plan(cached: [], observed: [])

        #expect(plan.reuse.isEmpty)
        #expect(plan.refresh.isEmpty)
        #expect(plan.remove.isEmpty)
    }

    @Test func repoObservedButNotCachedIsRefreshedAsNew() {
        let fresh = entry("/dev/new", head: "aaa")

        let plan = IncrementalRescanPlanner().plan(cached: [], observed: [fresh])

        #expect(plan.refresh == [fresh])
        #expect(plan.reuse.isEmpty)
        #expect(plan.remove.isEmpty)
    }

    @Test func repoCachedButNoLongerOnDiskIsRemoved() {
        let gone = entry("/dev/gone", head: "bbb")

        let plan = IncrementalRescanPlanner().plan(cached: [gone], observed: [])

        #expect(plan.remove == [gone])
        #expect(plan.reuse.isEmpty)
        #expect(plan.refresh.isEmpty)
    }

    @Test func unchangedHeadIsReusedFromTheCachedRowNotReRead() {
        // Same path + same HEAD: reuse carries the *cached* row (its older lastScanned proves
        // we kept it rather than re-reading), so no git work is scheduled for it.
        let cached = IndexEntry(path: "/dev/app", headSHA: "ccc", lastScanned: t0)
        let observed = IndexEntry(path: "/dev/app", headSHA: "ccc",
                                  lastScanned: t0.addingTimeInterval(3600))

        let plan = IncrementalRescanPlanner().plan(cached: [cached], observed: [observed])

        #expect(plan.reuse == [cached])
        #expect(plan.refresh.isEmpty)
        #expect(plan.remove.isEmpty)
    }

    @Test func movedHeadIsRefreshed() {
        let cached = entry("/dev/app", head: "ccc")
        let moved = entry("/dev/app", head: "ddd")

        let plan = IncrementalRescanPlanner().plan(cached: [cached], observed: [moved])

        #expect(plan.refresh == [moved])
        #expect(plan.reuse.isEmpty)
        #expect(plan.remove.isEmpty)
    }

    @Test func headBecomingReadableIsRefreshed() {
        // A repo we'd indexed before HEAD existed (nil) now has its first commit → re-read it.
        let cached = entry("/dev/fresh", head: nil)
        let nowHasHead = entry("/dev/fresh", head: "eee")

        let plan = IncrementalRescanPlanner().plan(cached: [cached], observed: [nowHasHead])

        #expect(plan.refresh == [nowHasHead])
        #expect(plan.reuse.isEmpty)
    }

    @Test func mixedScanBucketsEveryRepoCorrectly() {
        let kept = entry("/dev/kept", head: "111")          // unchanged → reuse
        let moved = entry("/dev/moved", head: "222")
        let movedNow = entry("/dev/moved", head: "999")     // HEAD moved → refresh
        let vanished = entry("/dev/vanished", head: "333")  // gone → remove
        let brandNew = entry("/dev/new", head: "444")       // new → refresh

        let plan = IncrementalRescanPlanner().plan(
            cached: [kept, moved, vanished],
            observed: [kept, movedNow, brandNew])

        #expect(plan.reuse == [kept])
        #expect(Set(plan.refresh.map(\.path)) == ["/dev/moved", "/dev/new"])
        #expect(plan.remove == [vanished])
    }
}
