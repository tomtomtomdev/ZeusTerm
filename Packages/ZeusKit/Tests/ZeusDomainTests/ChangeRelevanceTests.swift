import Foundation
import Testing
@testable import ZeusDomain

/// P3-D.3a — the pure filter that decides whether a filesystem change reported by the
/// FSEvents watcher (the `FileSystemWatching` port) is worth a Hub rescan. FSEvents fires
/// bursts for *any* change under the watched roots — including `npm install` churn under
/// `node_modules` and Xcode writing into `DerivedData`/`.build` — and a rescan walks the
/// tree + shells out to `git`, so we drop changes whose path runs through a pruned dir.
/// Pure: a predicate over a path string + the pruned-dir set. No FS, no git, no clock.
///
/// Test List:
///  [x] a change under a project's own source tree            → relevant
///  [x] a change inside `node_modules`                         → irrelevant
///  [x] a change inside `.build` / `DerivedData` (triangulate) → irrelevant
///  [x] a `.git` change (commit / HEAD move)                   → relevant (status/HEAD shifts)
///  [x] the pruned set is injectable                           → custom set honored
struct ChangeRelevanceTests {

    @Test func aChangeInAProjectSourceTreeIsRelevant() {
        let relevance = ChangeRelevance()

        #expect(relevance.isRelevant(changedPath: "/Users/me/Projects/app/Sources/main.swift"))
    }

    @Test func aChangeInsideNodeModulesIsIrrelevant() {
        let relevance = ChangeRelevance()

        #expect(!relevance.isRelevant(changedPath: "/Users/me/Projects/app/node_modules/x/index.js"))
    }

    @Test(arguments: [
        "/Users/me/Projects/app/.build/checkouts/dep/Sources/x.swift",
        "/Users/me/Library/Developer/Xcode/DerivedData/App-abc/Build/Products/x.o",
    ])
    func aChangeInsideABuildOutputDirIsIrrelevant(path: String) {
        #expect(!ChangeRelevance().isRelevant(changedPath: path))
    }

    @Test func aGitChangeStaysRelevantSoCommitsAndStatusFlipsRefresh() {
        // A commit moves HEAD and `git status` flips on working-tree edits; both surface as
        // `.git` writes. `.git` is deliberately NOT pruned, so these still trigger a rescan.
        let relevance = ChangeRelevance()

        #expect(relevance.isRelevant(changedPath: "/Users/me/Projects/app/.git/HEAD"))
    }

    @Test func thePrunedSetIsInjectable() {
        let relevance = ChangeRelevance(prunedDirectoryNames: ["ignored"])

        #expect(!relevance.isRelevant(changedPath: "/Users/me/Projects/app/ignored/x"))
        // node_modules is no longer pruned under the custom set.
        #expect(relevance.isRelevant(changedPath: "/Users/me/Projects/app/node_modules/x"))
    }
}
