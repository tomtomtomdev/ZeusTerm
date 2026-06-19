import Testing
import Foundation
@testable import ZeusDomain

struct CommitGraphLayoutTests {

    @Test func ranksTopologicallyWithNewestAtTop() {
        // Linear chain a ← b ← c on main; HEAD is the middle commit b.
        let commits = [
            GraphCommit(sha: "a", summary: "init", branch: "main", parents: []),
            GraphCommit(sha: "b", summary: "feat", branch: "main", parents: ["a"]),
            GraphCommit(sha: "c", summary: "wip",  branch: "main", parents: ["b"]),
        ]
        let tree = CommitGraphLayout().buildTree(commits: commits, lanes: ["main": 430], head: "b")
        let node = Dictionary(uniqueKeysWithValues: tree.nodes.map { ($0.id, $0) })

        // child rank > parent rank
        #expect(node["a"]!.rank < node["b"]!.rank)
        #expect(node["b"]!.rank < node["c"]!.rank)
        // newest commit sits highest on screen (smallest y)
        #expect(node["c"]!.point.y < node["a"]!.point.y)
        // lane x from the mapping
        #expect(node["a"]!.point.x == 430)
        // HEAD flag + dimming of commits newer than HEAD
        #expect(node["b"]!.isHead)
        #expect(node["c"]!.isDim)
        #expect(!node["a"]!.isDim && !node["b"]!.isDim)
        // one edge per present parent link: b→a, c→b
        #expect(tree.edges.count == 2)
    }

    @Test func assignsLanesPerBranchAndLinksAcrossBranches() {
        // a(main) ← b(main) ← f(feature); HEAD is the tip f.
        let commits = [
            GraphCommit(sha: "a", summary: "a", branch: "main", parents: []),
            GraphCommit(sha: "b", summary: "b", branch: "main", parents: ["a"]),
            GraphCommit(sha: "f", summary: "f", branch: "feature", parents: ["b"]),
        ]
        let tree = CommitGraphLayout().buildTree(
            commits: commits, lanes: ["main": 430, "feature": 580], head: "f")
        let node = Dictionary(uniqueKeysWithValues: tree.nodes.map { ($0.id, $0) })

        #expect(node["b"]!.point.x == 430)
        #expect(node["f"]!.point.x == 580)
        #expect(tree.nodes.allSatisfy { !$0.isDim })   // HEAD is the tip → nothing newer

        // the cross-branch edge is colored by the child's branch and joins f → b
        let crossEdge = try! #require(tree.edges.first { $0.branch == "feature" })
        #expect(crossEdge.from == node["f"]!.point)
        #expect(crossEdge.to == node["b"]!.point)
    }
}
