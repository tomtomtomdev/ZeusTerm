import Foundation

/// Pure use case: lays out the branch-tree commit graph (SPEC §7, View 3).
/// Time flows top→bottom: a commit's vertical position comes from its **topological
/// rank** (derived from `parents`, not a hand-assigned time index), so the newest commit
/// sits at the top and edges never imply a child is older than its parent. Branch lanes
/// supply the x columns; commits newer than HEAD are dimmed.
public struct CommitGraphLayout: Sendable {
    public init() {}

    public func buildTree(commits: [GraphCommit],
                          lanes: [String: Double],
                          head: String,
                          rowHeight: Double = 80,
                          topY: Double = 75) -> ConstellationTree {
        let bySha = Dictionary(commits.map { ($0.sha, $0) }, uniquingKeysWith: { a, _ in a })

        // Topological rank: roots = 0; otherwise 1 + max(present parents' ranks).
        var rankCache: [String: Int] = [:]
        func rank(of sha: String) -> Int {
            if let cached = rankCache[sha] { return cached }
            let presentParents = bySha[sha]?.parents.filter { bySha[$0] != nil } ?? []
            let value = presentParents.isEmpty ? 0 : 1 + presentParents.map(rank(of:)).max()!
            rankCache[sha] = value
            return value
        }
        let ranks = Dictionary(uniqueKeysWithValues: commits.map { ($0.sha, rank(of: $0.sha)) })
        let maxRank = ranks.values.max() ?? 0
        let headRank = ranks[head] ?? maxRank
        let fallbackLane = lanes.values.min() ?? 0

        func point(_ commit: GraphCommit) -> StagePoint {
            StagePoint(x: lanes[commit.branch] ?? fallbackLane,
                       y: topY + Double(maxRank - ranks[commit.sha]!) * rowHeight)
        }

        let nodes = commits.map { commit in
            CommitNode(id: commit.sha, branch: commit.branch, summary: commit.summary,
                       point: point(commit), rank: ranks[commit.sha]!,
                       isHead: commit.sha == head, isDim: ranks[commit.sha]! > headRank)
        }

        let edges = commits.flatMap { commit in
            commit.parents.compactMap { parentSha -> CommitEdge? in
                guard let parent = bySha[parentSha] else { return nil }
                return CommitEdge(from: point(commit), to: point(parent), branch: commit.branch)
            }
        }

        return ConstellationTree(nodes: nodes, edges: edges)
    }
}
