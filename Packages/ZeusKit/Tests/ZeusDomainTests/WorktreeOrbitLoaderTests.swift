import Testing
import Foundation
@testable import ZeusDomain

/// The pure orchestration use case behind the worktree (orbit) level: reads a repo's real
/// worktrees and per-worktree status through `GitReading`, mapping each to the `WorktreeInput`
/// the layout places as a satellite. Tested with a hand-written Stub — no disk, no git CLI.
struct WorktreeOrbitLoaderTests {

    private struct StubGit: GitReading {
        var repository: Repository
        var statuses: [String: GitStatus] = [:]
        var failingStatusPaths: Set<String> = []
        func readRepository(at url: URL) async throws -> Repository { repository }
        func status(at url: URL) async throws -> GitStatus {
            if failingStatusPaths.contains(url.path) { throw StubError.status }
            return statuses[url.path] ?? .clean
        }
        // Not exercised by the orbit loader — fail loudly if the orchestration drifts.
        func commits(forBranch: String, in repo: URL, limit: Int, skip: Int) async throws -> [Commit] {
            fatalError("unused")
        }
        func diff(forCommit sha: String, in repo: URL) async throws -> CommitDiff { fatalError("unused") }
        func headSHA(at url: URL) async throws -> String? { fatalError("unused") }
    }
    private enum StubError: Error { case status }

    @Test func mapsEachWorktreeToItsCheckedOutBranchNameAndStatus() async throws {
        let main = URL(fileURLWithPath: "/code/api")
        let hotfix = URL(fileURLWithPath: "/code/api-hotfix")
        let repo = Repository(name: "api", commonDir: main, worktrees: [
            Worktree(path: main, isMain: true,
                     branches: [Branch(name: "main", isCurrent: true), Branch(name: "dev")]),
            Worktree(path: hotfix, isMain: false,
                     branches: [Branch(name: "hotfix/payment", isCurrent: true)]),
        ])
        let git = StubGit(repository: repo, statuses: ["/code/api": .clean, "/code/api-hotfix": .dirty])

        let inputs = try await WorktreeOrbitLoader(git: git).load(repoPath: main)

        #expect(inputs == [
            WorktreeInput(branch: "main", name: "api", status: .clean),
            WorktreeInput(branch: "hotfix/payment", name: "api-hotfix", status: .dirty),
        ])
    }

    @Test func aWorktreeWithNoCheckedOutBranchIsLabelledDetached() async throws {
        let main = URL(fileURLWithPath: "/code/api")
        let repo = Repository(name: "api", commonDir: main, worktrees: [
            Worktree(path: main, isMain: true, branches: []),   // no current branch → detached HEAD
        ])
        let git = StubGit(repository: repo, statuses: ["/code/api": .ahead])

        let inputs = try await WorktreeOrbitLoader(git: git).load(repoPath: main)

        #expect(inputs == [WorktreeInput(branch: "(detached)", name: "api", status: .ahead)])
    }

    @Test func aFailedStatusReadForOneWorktreeFallsBackToCleanWithoutAborting() async throws {
        let main = URL(fileURLWithPath: "/code/api")
        let broken = URL(fileURLWithPath: "/code/api-broken")
        let repo = Repository(name: "api", commonDir: main, worktrees: [
            Worktree(path: main, isMain: true, branches: [Branch(name: "main", isCurrent: true)]),
            Worktree(path: broken, isMain: false, branches: [Branch(name: "spike", isCurrent: true)]),
        ])
        let git = StubGit(repository: repo,
                          statuses: ["/code/api": .dirty],
                          failingStatusPaths: ["/code/api-broken"])

        let inputs = try await WorktreeOrbitLoader(git: git).load(repoPath: main)

        #expect(inputs == [
            WorktreeInput(branch: "main", name: "api", status: .dirty),
            WorktreeInput(branch: "spike", name: "api-broken", status: .clean),   // neutral fallback
        ])
    }
}
