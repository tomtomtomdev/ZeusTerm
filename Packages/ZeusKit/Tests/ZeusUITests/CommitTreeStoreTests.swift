import Testing
import Foundation
import ZeusDomain
@testable import ZeusUI

/// The UI-side store driving the branch-tree level: runs the pure `CommitTreeLoader` (off-main)
/// for a dived-into worktree's branch and publishes the laid-out `ConstellationTree` + the branch
/// tip. Same cancellable-single-task discipline as `WorktreeOrbitStore` (a new dive supersedes any
/// in-flight load). Tested with stub `GitReading`s — no disk, no git CLI.
@MainActor
struct CommitTreeStoreTests {

    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    private struct StubGit: GitReading {
        var commitsByBranch: [String: [Commit]]
        func commits(forBranch branch: String, in repo: URL, limit: Int, skip: Int) async throws -> [Commit] {
            commitsByBranch[branch] ?? []
        }
        func readRepository(at url: URL) async throws -> Repository { fatalError("unused") }
        func diff(forCommit sha: String, in repo: URL) async throws -> CommitDiff { fatalError("unused") }
        func status(at url: URL) async throws -> GitStatus { fatalError("unused") }
        func headSHA(at url: URL) async throws -> String? { fatalError("unused") }
    }

    private struct FailingGit: GitReading {
        func commits(forBranch branch: String, in repo: URL, limit: Int, skip: Int) async throws -> [Commit] {
            throw StubError.fail
        }
        func readRepository(at url: URL) async throws -> Repository { fatalError("unused") }
        func diff(forCommit sha: String, in repo: URL) async throws -> CommitDiff { fatalError("unused") }
        func status(at url: URL) async throws -> GitStatus { fatalError("unused") }
        func headSHA(at url: URL) async throws -> String? { fatalError("unused") }
    }
    private enum StubError: Error { case fail }

    private func linearHistory(_ branch: String, shas: [String]) -> [String: [Commit]] {
        // shas newest-first; each commit's parent is the next (older) sha.
        let commits = shas.enumerated().map { i, sha in
            Commit(id: sha, summary: sha, authorName: "a", date: date,
                   parents: i + 1 < shas.count ? [shas[i + 1]] : [])
        }
        return [branch: commits]
    }

    private func store(_ git: any GitReading) -> CommitTreeStore {
        CommitTreeStore(loader: CommitTreeLoader(git: git))
    }

    @Test func loadPublishesTheLaidOutTreeNewestFirstAndTheBranchTip() async throws {
        let s = store(StubGit(commitsByBranch: linearHistory("develop", shas: ["c3", "c2", "c1"])))

        s.load(repoPath: URL(fileURLWithPath: "/code/api"), branch: "develop")
        await s.waitForLoad()

        let tree = try #require(s.tree)
        #expect(s.tip == "c3")                                   // newest commit is the tip
        #expect(tree.nodes.map(\.id) == ["c3", "c2", "c1"])
        #expect(tree.nodes.allSatisfy { $0.branch == "develop" })
        let c3 = try #require(tree.nodes.first { $0.id == "c3" })
        let c1 = try #require(tree.nodes.first { $0.id == "c1" })
        #expect(c3.point.y < c1.point.y)                         // newest sits above oldest
    }

    @Test func aFailedHistoryReadPublishesAnEmptyTreeWithNoTip() async throws {
        let s = store(FailingGit())

        s.load(repoPath: URL(fileURLWithPath: "/gone"), branch: "main")
        await s.waitForLoad()

        let tree = try #require(s.tree)
        #expect(tree.nodes.isEmpty)
        #expect(s.tip == nil)
    }

    @Test func startingANewLoadImmediatelyClearsThePreviousBranchTree() async throws {
        var byBranch = linearHistory("a", shas: ["a2", "a1"])
        byBranch.merge(linearHistory("b", shas: ["b2", "b1"])) { x, _ in x }
        let s = store(StubGit(commitsByBranch: byBranch))

        s.load(repoPath: URL(fileURLWithPath: "/code/r"), branch: "a")
        await s.waitForLoad()
        #expect(s.tip == "a2")

        s.load(repoPath: URL(fileURLWithPath: "/code/r"), branch: "b")
        #expect(s.tree == nil)                                   // cleared synchronously, no stale-a flash
        #expect(s.tip == nil)

        await s.waitForLoad()
        #expect(s.tip == "b2")
        #expect(s.tree?.nodes.map(\.id) == ["b2", "b1"])
    }
}
