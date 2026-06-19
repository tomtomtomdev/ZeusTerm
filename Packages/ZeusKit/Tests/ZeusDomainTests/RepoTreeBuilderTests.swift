import Testing
import Foundation
@testable import ZeusDomain

struct RepoTreeBuilderTests {

    private func sampleRepository() -> Repository {
        let commit = Commit(id: "a1b2c3d", summary: "fix CI", authorName: "tom",
                            date: Date(timeIntervalSince1970: 0))
        let main = Branch(name: "main", isCurrent: true, ahead: 1, behind: 0, commits: [commit])
        let feature = Branch(name: "feature", isCurrent: false)
        let worktree = Worktree(path: URL(fileURLWithPath: "/repo"), isMain: true,
                                branches: [main, feature])
        return Repository(name: "app", commonDir: URL(fileURLWithPath: "/repo/.git"),
                          worktrees: [worktree])
    }

    @Test func buildsRepoWorktreeBranchCommitHierarchy() {
        let node = RepoTreeBuilder().build(from: sampleRepository())

        #expect(node.kind == .repository)
        #expect(node.title == "app")
        #expect(node.children.count == 1)

        let worktree = node.children[0]
        #expect(worktree.kind == .worktree)
        #expect(worktree.children.count == 2)

        let mainBranch = worktree.children[0]
        #expect(mainBranch.kind == .branch)
        #expect(mainBranch.title == "main")
        #expect(mainBranch.badge?.contains("current") == true)
        #expect(mainBranch.badge?.contains("↑1") == true)
        #expect(mainBranch.children.count == 1)

        let commit = mainBranch.children[0]
        #expect(commit.kind == .commit)
        #expect(commit.title == "fix CI")
    }

    @Test func buildsForestFromProjects() {
        let project = Project(id: UUID(), name: "app",
                              rootURL: URL(fileURLWithPath: "/repo"),
                              repository: sampleRepository())
        let forest = RepoTreeBuilder().build(from: [project])
        #expect(forest.count == 1)
        #expect(forest[0].kind == .repository)
    }
}
