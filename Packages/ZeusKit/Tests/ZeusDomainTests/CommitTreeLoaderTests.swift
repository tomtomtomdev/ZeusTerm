import Testing
import Foundation
@testable import ZeusDomain

/// The pure orchestration use case behind the branch-tree level: reads a worktree's branch
/// history through `GitReading` and maps each commit to the `GraphCommit` the graph layout ranks
/// and places. First cut shows the checked-out branch's linear history in one lane; a multi-branch
/// graph (the prototype's merges across lanes) is a later refinement. Tested with a stub — no git.
struct CommitTreeLoaderTests {

    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    private struct StubGit: GitReading {
        var commitsByBranch: [String: [Commit]]
        var capturedLimit: Int?
        func commits(forBranch branch: String, in repo: URL, limit: Int, skip: Int) async throws -> [Commit] {
            commitsByBranch[branch] ?? []
        }
        // Not exercised by the tree loader — fail loudly if the orchestration drifts.
        func readRepository(at url: URL) async throws -> Repository { fatalError("unused") }
        func diff(forCommit sha: String, in repo: URL) async throws -> CommitDiff { fatalError("unused") }
        func status(at url: URL) async throws -> GitStatus { fatalError("unused") }
        func headSHA(at url: URL) async throws -> String? { fatalError("unused") }
    }

    @Test func loadsTheBranchHistoryAsGraphCommitsPreservingOrderAndParents() async throws {
        let repo = URL(fileURLWithPath: "/code/api")
        let git = StubGit(commitsByBranch: ["develop": [
            Commit(id: "c3", summary: "newest", authorName: "a", date: date, parents: ["c2"]),
            Commit(id: "c2", summary: "mid",    authorName: "a", date: date, parents: ["c1"]),
            Commit(id: "c1", summary: "first",  authorName: "a", date: date, parents: []),
        ]])

        let graph = try await CommitTreeLoader(git: git).load(repoPath: repo, branch: "develop")

        #expect(graph == [
            GraphCommit(sha: "c3", summary: "newest", branch: "develop", parents: ["c2"]),
            GraphCommit(sha: "c2", summary: "mid",    branch: "develop", parents: ["c1"]),
            GraphCommit(sha: "c1", summary: "first",  branch: "develop", parents: []),
        ])
    }
}
