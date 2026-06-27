import Testing
import Foundation
import ZeusDomain
@testable import ZeusUI

/// The UI-side store driving the branch-tree Changes panel (slice 6): runs the pure
/// `CommitDiffLoader` (off-main) for the selected commit and publishes its `CommitDiff`. Same
/// cancellable-single-task discipline as `CommitTreeStore` / `WorktreeOrbitStore` — selecting a new
/// commit supersedes any in-flight load. Tested with stub `GitReading`s — no disk, no git CLI.
@MainActor
struct CommitDiffStoreTests {

    private struct StubGit: GitReading {
        var diffsBySHA: [String: CommitDiff]
        func diff(forCommit sha: String, in repo: URL) async throws -> CommitDiff {
            diffsBySHA[sha] ?? CommitDiff(sha: sha, files: [], patch: "")
        }
        func readRepository(at url: URL) async throws -> Repository { fatalError("unused") }
        func commits(forBranch branch: String, in repo: URL, limit: Int, skip: Int) async throws -> [Commit] { fatalError("unused") }
        func status(at url: URL) async throws -> GitStatus { fatalError("unused") }
        func headSHA(at url: URL) async throws -> String? { fatalError("unused") }
    }

    private struct FailingGit: GitReading {
        func diff(forCommit sha: String, in repo: URL) async throws -> CommitDiff { throw StubError.fail }
        func readRepository(at url: URL) async throws -> Repository { fatalError("unused") }
        func commits(forBranch branch: String, in repo: URL, limit: Int, skip: Int) async throws -> [Commit] { fatalError("unused") }
        func status(at url: URL) async throws -> GitStatus { fatalError("unused") }
        func headSHA(at url: URL) async throws -> String? { fatalError("unused") }
    }
    private enum StubError: Error { case fail }

    private func store(_ git: any GitReading) -> CommitDiffStore {
        CommitDiffStore(loader: CommitDiffLoader(git: git))
    }

    private func sampleDiff(_ sha: String) -> CommitDiff {
        CommitDiff(sha: sha, files: [
            FileChange(path: "A.swift", status: .modified, additions: 2, deletions: 1),
        ], patch: "@@\n-old\n+new\n")
    }

    @Test func startsWithNoDiff() {
        #expect(store(StubGit(diffsBySHA: [:])).diff == nil)
    }

    @Test func loadPublishesTheDiffForTheSelectedCommit() async throws {
        let s = store(StubGit(diffsBySHA: ["c2": sampleDiff("c2")]))

        s.load(repoPath: URL(fileURLWithPath: "/code/api"), sha: "c2")
        await s.waitForLoad()

        #expect(s.diff == sampleDiff("c2"))
    }

    @Test func startingANewLoadImmediatelyClearsThePreviousDiff() async throws {
        let s = store(StubGit(diffsBySHA: ["c1": sampleDiff("c1"), "c2": sampleDiff("c2")]))

        s.load(repoPath: URL(fileURLWithPath: "/code/api"), sha: "c1")
        await s.waitForLoad()
        #expect(s.diff == sampleDiff("c1"))

        s.load(repoPath: URL(fileURLWithPath: "/code/api"), sha: "c2")
        #expect(s.diff == nil)                                   // cleared synchronously, no stale-c1 flash

        await s.waitForLoad()
        #expect(s.diff == sampleDiff("c2"))
    }

    @Test func aFailedReadPublishesAnEmptyDiffForThatSha() async throws {
        let s = store(FailingGit())

        s.load(repoPath: URL(fileURLWithPath: "/gone"), sha: "deadbee")
        await s.waitForLoad()

        let diff = try #require(s.diff)
        #expect(diff == CommitDiff(sha: "deadbee", files: [], patch: ""))
    }
}
