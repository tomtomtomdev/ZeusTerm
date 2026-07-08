import Testing
import Foundation
import ZeusDomain
@testable import ZeusUI

/// The UI-side store driving the worktree (orbit) level: it runs the pure `WorktreeOrbitLoader`
/// (off-main) for a dived-into repo and publishes the laid-out `SideOnOrbits` the view renders.
/// Like `HubDataStore`, a new dive supersedes any in-flight load so the level always reflects the
/// latest repo. Tested with stub `GitReading`s — no disk, no git CLI.
@MainActor
struct WorktreeOrbitStoreTests {

    private struct StubGit: GitReading {
        var repositories: [String: Repository]
        var statuses: [String: GitStatus] = [:]
        func readRepository(at url: URL) async throws -> Repository {
            guard let repo = repositories[url.path] else { throw StubError.missing }
            return repo
        }
        func status(at url: URL) async throws -> GitStatus { statuses[url.path] ?? .clean }
        func commits(forBranch: String, in repo: URL, limit: Int, skip: Int) async throws -> [Commit] {
            fatalError("unused")
        }
        func diff(forCommit sha: String, in repo: URL) async throws -> CommitDiff { fatalError("unused") }
        func headSHA(at url: URL) async throws -> String? { fatalError("unused") }
    }

    private struct FailingGit: GitReading {
        func readRepository(at url: URL) async throws -> Repository { throw StubError.missing }
        func status(at url: URL) async throws -> GitStatus { .clean }
        func commits(forBranch: String, in repo: URL, limit: Int, skip: Int) async throws -> [Commit] { [] }
        func diff(forCommit sha: String, in repo: URL) async throws -> CommitDiff { CommitDiff(sha: "", files: [], patch: "") }
        func headSHA(at url: URL) async throws -> String? { nil }
    }

    /// Suspends `readRepository` for one path until the test opens it — forces a slow earlier load
    /// to finish *after* a newer one, the exact out-of-order timing the supersede guard must beat.
    private actor Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var opened = false
        func wait() async {
            if opened { return }
            await withCheckedContinuation { continuation = $0 }
        }
        func open() {
            opened = true
            continuation?.resume()
            continuation = nil
        }
    }

    private struct GatedGit: GitReading {
        var repositories: [String: Repository]
        var gate: Gate
        var gatedPath: String
        func readRepository(at url: URL) async throws -> Repository {
            if url.path == gatedPath { await gate.wait() }
            guard let repo = repositories[url.path] else { throw StubError.missing }
            return repo
        }
        func status(at url: URL) async throws -> GitStatus { .clean }
        func commits(forBranch: String, in repo: URL, limit: Int, skip: Int) async throws -> [Commit] {
            fatalError("unused")
        }
        func diff(forCommit sha: String, in repo: URL) async throws -> CommitDiff { fatalError("unused") }
        func headSHA(at url: URL) async throws -> String? { fatalError("unused") }
    }

    private enum StubError: Error { case missing }

    /// A one-worktree repo at `/code/<name>` checked out on `branch`.
    private func repo(_ name: String, branch: String) -> Repository {
        let url = URL(fileURLWithPath: "/code/\(name)")
        return Repository(name: name, commonDir: url, worktrees: [
            Worktree(path: url, isMain: true, branches: [Branch(name: branch, isCurrent: true)]),
        ])
    }

    @Test func loadPublishesLaidOutOrbitsForTheReposRealWorktrees() async throws {
        let main = URL(fileURLWithPath: "/code/api")
        let hotfix = URL(fileURLWithPath: "/code/api-hotfix")
        let repository = Repository(name: "api", commonDir: main, worktrees: [
            Worktree(path: main, isMain: true, branches: [Branch(name: "main", isCurrent: true)]),
            Worktree(path: hotfix, isMain: false, branches: [Branch(name: "hotfix", isCurrent: true)]),
        ])
        let git = StubGit(repositories: ["/code/api": repository],
                          statuses: ["/code/api": .clean, "/code/api-hotfix": .dirty])
        let s = WorktreeOrbitStore(loader: WorktreeOrbitLoader(git: git))

        s.load(repoPath: main)
        await s.waitForLoad()

        let orbits = try #require(s.orbits)
        #expect(orbits.planets.map(\.branch) == ["main", "hotfix"])
        #expect(orbits.planets.map(\.status) == [.clean, .dirty])
        #expect(orbits.planets.count == 2)                     // one orbit per worktree
        #expect(orbits.center.point == StagePoint(x: 512, y: 262))
        #expect(orbits.center.name == "api")                   // the dived-into repo, from its path
        #expect(orbits.center.status == .clean)                // mirrors the main worktree (/code/api)
    }

    @Test func aFailedRepositoryReadLeavesJustTheCentralStarNotAStaleOrbit() async throws {
        let s = WorktreeOrbitStore(loader: WorktreeOrbitLoader(git: FailingGit()))

        s.load(repoPath: URL(fileURLWithPath: "/gone"))
        await s.waitForLoad()

        let orbits = try #require(s.orbits)                    // published, not left nil
        #expect(orbits.planets.isEmpty)
    }

    @Test func startingANewLoadImmediatelyClearsThePreviousReposOrbits() async throws {
        let git = StubGit(repositories: ["/code/a": repo("a", branch: "a-main"),
                                         "/code/b": repo("b", branch: "b-main")])
        let s = WorktreeOrbitStore(loader: WorktreeOrbitLoader(git: git))

        s.load(repoPath: URL(fileURLWithPath: "/code/a"))
        await s.waitForLoad()
        #expect(s.orbits?.planets.map(\.branch) == ["a-main"])

        // Diving into b clears a's orbits synchronously — no stale-a flash while b loads.
        s.load(repoPath: URL(fileURLWithPath: "/code/b"))
        #expect(s.orbits == nil)

        await s.waitForLoad()
        #expect(s.orbits?.planets.map(\.branch) == ["b-main"])
    }

    @Test func anInFlightLoadIsSupersededByANewerDiveAndCannotClobberIt() async throws {
        let gate = Gate()
        let git = GatedGit(repositories: ["/code/a": repo("a", branch: "a-main"),
                                          "/code/b": repo("b", branch: "b-main")],
                           gate: gate, gatedPath: "/code/a")
        let s = WorktreeOrbitStore(loader: WorktreeOrbitLoader(git: git))

        s.load(repoPath: URL(fileURLWithPath: "/code/a"))   // suspends in readRepository on the gate
        s.load(repoPath: URL(fileURLWithPath: "/code/b"))   // supersedes a; b is ungated
        await s.waitForLoad()                               // awaits the latest (b)
        #expect(s.orbits?.planets.map(\.branch) == ["b-main"])

        await gate.open()                                   // let a's superseded load drain
        await Task.yield()
        #expect(s.orbits?.planets.map(\.branch) == ["b-main"])   // a did not clobber b
    }
}
