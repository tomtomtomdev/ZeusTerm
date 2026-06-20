import Testing
import Foundation
import ZeusDomain
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
        // Unit-separated (US, 0x1f): %H %s %an %aI %P, one commit per line.
        // %P is a space-separated parent list (empty for a root commit).
        let us = "\u{1f}"
        let sample = """
        a1b2c3d4\(us)fix CI\(us)tom\(us)1970-01-01T00:00:01Z\(us)p1 p2
        9f3da2b1\(us)add tests\(us)alice\(us)1970-01-01T00:00:02Z\(us)
        """
        let commits = GitCLIService().parseCommits(sample)

        #expect(commits.count == 2)
        #expect(commits[0].id == "a1b2c3d4")
        #expect(commits[0].summary == "fix CI")
        #expect(commits[0].authorName == "tom")
        #expect(commits[0].date == Date(timeIntervalSince1970: 1))
        #expect(commits[0].parents == ["p1", "p2"])
        #expect(commits[1].id == "9f3da2b1")
        #expect(commits[1].summary == "add tests")
        #expect(commits[1].date == Date(timeIntervalSince1970: 2))
        #expect(commits[1].parents == [])
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

    @Test func parsesFileChangesFromNumstatAndNameStatus() {
        let numstat = "10\t2\tsrc/a.swift\n5\t0\tsrc/b.swift\n0\t8\tsrc/c.swift"
        let nameStatus = "M\tsrc/a.swift\nA\tsrc/b.swift\nD\tsrc/c.swift"
        let changes = GitCLIService().parseFileChanges(numstat: numstat, nameStatus: nameStatus)

        #expect(changes.count == 3)
        #expect(changes[0] == FileChange(path: "src/a.swift", status: .modified, additions: 10, deletions: 2))
        #expect(changes[1].status == .added)
        #expect(changes[1].additions == 5)
        #expect(changes[2].status == .deleted)
        #expect(changes[2].deletions == 8)
    }

    // MARK: - Overall status parsing (git status --porcelain=v2 --branch)

    @Test func parsesStatusDirtyWhenTrackedFilesChanged() {
        let sample = """
        # branch.oid abc123
        # branch.head main
        1 .M N... 100644 100644 100644 aaa bbb file.txt
        """
        #expect(GitCLIService().parseStatus(sample) == .dirty)
    }

    @Test func parsesStatusUntrackedWhenOnlyUntrackedFiles() {
        let sample = """
        # branch.head main
        ? newfile.txt
        """
        #expect(GitCLIService().parseStatus(sample) == .untracked)
    }

    @Test func parsesStatusAheadWhenCleanButAheadOfUpstream() {
        let sample = """
        # branch.head main
        # branch.upstream origin/main
        # branch.ab +2 -0
        """
        #expect(GitCLIService().parseStatus(sample) == .ahead)
    }

    @Test func parsesStatusBehindWhenCleanButBehindUpstream() {
        let sample = """
        # branch.head main
        # branch.upstream origin/main
        # branch.ab +0 -3
        """
        #expect(GitCLIService().parseStatus(sample) == .behind)
    }

    @Test func parsesStatusCleanWhenNothingPending() {
        let sample = """
        # branch.head main
        # branch.upstream origin/main
        # branch.ab +0 -0
        """
        #expect(GitCLIService().parseStatus(sample) == .clean)
    }

    @Test func statusPrecedenceFavorsDirtyOverUntrackedAndAhead() {
        let sample = """
        # branch.ab +5 -1
        1 .M N... 100644 100644 100644 aaa bbb file.txt
        ? newfile.txt
        """
        #expect(GitCLIService().parseStatus(sample) == .dirty)
    }

    @Test func statusPrecedenceFavorsAheadOverBehindWhenDiverged() {
        let sample = "# branch.ab +2 -3"
        #expect(GitCLIService().parseStatus(sample) == .ahead)
    }

    @Test func readsCleanStatusForCommittedRepo() async throws {
        let repo = makeFixtureRepo()
        defer { try? FileManager.default.removeItem(at: repo) }

        let status = try await GitCLIService().status(at: repo)
        #expect(status == .clean)
    }

    @Test func readsDirtyStatusWhenTrackedFileModified() async throws {
        let repo = makeFixtureRepo()       // README.md committed in "fix CI"
        defer { try? FileManager.default.removeItem(at: repo) }
        try! "changed".write(to: repo.appendingPathComponent("README.md"),
                             atomically: true, encoding: .utf8)

        let status = try await GitCLIService().status(at: repo)
        #expect(status == .dirty)
    }

    @Test func readsUntrackedStatusWhenNewFileAdded() async throws {
        let repo = makeFixtureRepo()
        defer { try? FileManager.default.removeItem(at: repo) }
        try! "new".write(to: repo.appendingPathComponent("NEW.md"),
                         atomically: true, encoding: .utf8)

        let status = try await GitCLIService().status(at: repo)
        #expect(status == .untracked)
    }

    @Test func readsCommitDiffWithFileChangesAndPatch() async throws {
        let repo = makeFixtureRepo()   // README.md added in "fix CI" on main
        defer { try? FileManager.default.removeItem(at: repo) }
        try! "hello world\nmore\n".write(to: repo.appendingPathComponent("README.md"),
                                         atomically: true, encoding: .utf8)
        git(["add", "."], in: repo)
        git(["commit", "-m", "update readme"], in: repo)
        let head = git(["rev-parse", "HEAD"], in: repo)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let diff = try await GitCLIService().diff(forCommit: head, in: repo)

        #expect(diff.sha == head)
        let file = try #require(diff.files.first { $0.path == "README.md" })
        #expect(file.status == .modified)
        #expect(file.additions >= 1)
        #expect(diff.patch.contains("README.md"))
    }
}
