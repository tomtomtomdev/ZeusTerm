import Testing
import Foundation
@testable import ZeusGit

struct GitCLIServiceTests {

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
}
