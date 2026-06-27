import Testing
import Foundation
@testable import ZeusDomain

/// The pure orchestration use case behind the branch-tree Changes panel (slice 6): reads one
/// commit's changed files + unified diff through `GitReading.diff`. Mirrors `CommitTreeLoader`
/// (I/O lives in the injected adapter), so it's unit-testable with a stub — no git CLI.
struct CommitDiffLoaderTests {

    /// Records the sha + repo it was asked for so the test can assert the loader forwards them,
    /// and returns a fixed diff keyed on that sha.
    private final class SpyGit: GitReading, @unchecked Sendable {
        let fixture: CommitDiff
        private(set) var capturedSHA: String?
        private(set) var capturedRepo: URL?
        init(fixture: CommitDiff) { self.fixture = fixture }

        func diff(forCommit sha: String, in repo: URL) async throws -> CommitDiff {
            capturedSHA = sha
            capturedRepo = repo
            return fixture
        }
        // Not exercised by the diff loader — fail loudly if the orchestration drifts.
        func readRepository(at url: URL) async throws -> Repository { fatalError("unused") }
        func commits(forBranch branch: String, in repo: URL, limit: Int, skip: Int) async throws -> [Commit] { fatalError("unused") }
        func status(at url: URL) async throws -> GitStatus { fatalError("unused") }
        func headSHA(at url: URL) async throws -> String? { fatalError("unused") }
    }

    @Test func loadsTheCommitDiffForwardingTheShaAndRepo() async throws {
        let repo = URL(fileURLWithPath: "/code/api")
        let fixture = CommitDiff(sha: "c2", files: [
            FileChange(path: "Sources/App.swift", status: .modified, additions: 4, deletions: 1),
            FileChange(path: "README.md", status: .added, additions: 9, deletions: 0),
        ], patch: "@@ -1 +1 @@\n-old\n+new\n")
        let git = SpyGit(fixture: fixture)

        let diff = try await CommitDiffLoader(git: git).load(repoPath: repo, sha: "c2")

        #expect(diff == fixture)
        #expect(git.capturedSHA == "c2")
        #expect(git.capturedRepo == repo)
    }
}
