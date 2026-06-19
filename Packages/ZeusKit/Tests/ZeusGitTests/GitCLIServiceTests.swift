import Testing
import Foundation
@testable import ZeusGit

struct GitCLIServiceTests {

    // MARK: - Fixture helpers (Fresh Fixture + Delegated Setup)

    /// Creates a fresh temp directory the caller is responsible for removing.
    private func makeTempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("zeus-git-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Runs `git` in `dir` with a deterministic identity + commit date.
    @discardableResult
    private func git(_ args: [String], in dir: URL) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        process.currentDirectoryURL = dir
        var env = ProcessInfo.processInfo.environment
        for key in ["GIT_AUTHOR_NAME", "GIT_COMMITTER_NAME"] { env[key] = "tom" }
        for key in ["GIT_AUTHOR_EMAIL", "GIT_COMMITTER_EMAIL"] { env[key] = "tom@example.com" }
        for key in ["GIT_AUTHOR_DATE", "GIT_COMMITTER_DATE"] { env[key] = "1970-01-01T00:00:01Z" }
        process.environment = env
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        try! process.run()
        process.waitUntilExit()
        return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    /// A repo on `main` with one commit ("fix CI") and an extra `feature` branch.
    private func makeFixtureRepo() -> URL {
        let repo = makeTempDir()
        git(["init", "-b", "main"], in: repo)
        try! "hello".write(to: repo.appendingPathComponent("README.md"),
                           atomically: true, encoding: .utf8)
        git(["add", "."], in: repo)
        git(["commit", "-m", "fix CI"], in: repo)
        git(["branch", "feature"], in: repo)
        return repo
    }

    @Test func reportsGitVersion() throws {
        let version = try GitCLIService().version()
        #expect(version.lowercased().contains("git"))
    }

    @Test func parsesWorktreePorcelain() {
        let sample = """
        worktree /Users/x/repo
        HEAD abc123
        branch refs/heads/main

        worktree /Users/x/repo-hotfix
        HEAD def456
        branch refs/heads/hotfix
        """
        let worktrees = GitCLIService().parseWorktrees(sample)

        #expect(worktrees.count == 2)
        #expect(worktrees[0].isMain)
        #expect(worktrees[0].currentBranch?.name == "main")
        #expect(worktrees[1].isMain == false)
        #expect(worktrees[1].currentBranch?.name == "hotfix")
    }

    @Test func parsesBranchRefs() {
        // Tab-separated: %(refname:short) %(HEAD) %(upstream:short) %(upstream:track)
        let sample = """
        main\t*\torigin/main\t[ahead 1, behind 2]
        feature\t \t\t
        release\t \torigin/release\t[behind 3]
        """
        let branches = GitCLIService().parseBranches(sample)

        #expect(branches.count == 3)

        #expect(branches[0].name == "main")
        #expect(branches[0].isCurrent)
        #expect(branches[0].upstream == "origin/main")
        #expect(branches[0].ahead == 1)
        #expect(branches[0].behind == 2)

        #expect(branches[1].name == "feature")
        #expect(branches[1].isCurrent == false)
        #expect(branches[1].upstream == nil)
        #expect(branches[1].ahead == 0)
        #expect(branches[1].behind == 0)

        #expect(branches[2].name == "release")
        #expect(branches[2].isCurrent == false)
        #expect(branches[2].upstream == "origin/release")
        #expect(branches[2].ahead == 0)
        #expect(branches[2].behind == 3)
    }

    @Test func parsesCommitLog() {
        // Unit-separated (US, 0x1f): %H %s %an %aI, one commit per line.
        let us = "\u{1f}"
        let sample = """
        a1b2c3d4\(us)fix CI\(us)tom\(us)1970-01-01T00:00:01Z
        9f3da2b1\(us)add tests\(us)alice\(us)1970-01-01T00:00:02Z
        """
        let commits = GitCLIService().parseCommits(sample)

        #expect(commits.count == 2)
        #expect(commits[0].id == "a1b2c3d4")
        #expect(commits[0].summary == "fix CI")
        #expect(commits[0].authorName == "tom")
        #expect(commits[0].date == Date(timeIntervalSince1970: 1))
        #expect(commits[1].id == "9f3da2b1")
        #expect(commits[1].summary == "add tests")
        #expect(commits[1].date == Date(timeIntervalSince1970: 2))
    }

    @Test func readsLocalBranchesIntoMainWorktree() async throws {
        let repo = makeFixtureRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        let repository = try await GitCLIService().readRepository(at: repo)
        let main = try #require(repository.mainWorktree)

        #expect(Set(main.branches.map(\.name)) == ["main", "feature"])
        #expect(main.currentBranch?.name == "main")
    }

    @Test func readsCommitsForBranchNewestFirstWithPagination() async throws {
        let repo = makeFixtureRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        // A second commit on main so ordering + pagination are observable.
        try! "world".write(to: repo.appendingPathComponent("CHANGES.md"),
                           atomically: true, encoding: .utf8)
        git(["add", "."], in: repo)
        git(["commit", "-m", "add tests"], in: repo)

        let service = GitCLIService()
        let all = try await service.commits(forBranch: "main", in: repo, limit: 10, skip: 0)
        #expect(all.map(\.summary) == ["add tests", "fix CI"])
        #expect(all.first?.authorName == "tom")

        // Pagination: skip the newest, take one.
        let page = try await service.commits(forBranch: "main", in: repo, limit: 1, skip: 1)
        #expect(page.map(\.summary) == ["fix CI"])
    }
}
