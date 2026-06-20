import Foundation
import ZeusDomain

/// Reads git data by shelling out to the `git` CLI (SPEC §5: libgit2's worktree bindings
/// are thin, so worktrees, branches, and commits all go through porcelain/format output).
/// Worktrees come from `git worktree list --porcelain`, branches from `git for-each-ref`,
/// and commits from a `git log` revwalk (paginated, never the full history).
public struct GitCLIService: GitReading {
    /// Field delimiter for `git log` rows — ASCII Unit Separator. Shared by the `--format`
    /// string and `parseCommits` so the producer and parser never drift apart.
    private static let fieldSeparator = "\u{1f}"

    public init() {}

    public func readRepository(at url: URL) async throws -> Repository {
        let top = try runGit(["rev-parse", "--show-toplevel"], in: url)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let root = URL(fileURLWithPath: top.isEmpty ? url.path : top)
        var worktrees = parseWorktrees(try runGit(["worktree", "list", "--porcelain"], in: root))

        // Branches are repo-level refs; surface the full local set under the main worktree
        // (linked worktrees keep their porcelain-derived checked-out branch).
        let branches = parseBranches(try runGit(branchRefArgs, in: root))
        if let mainIndex = worktrees.firstIndex(where: \.isMain) {
            worktrees[mainIndex].branches = branches
        }
        return Repository(name: root.lastPathComponent, commonDir: root, worktrees: worktrees)
    }

    public func commits(forBranch branch: String, in repo: URL, limit: Int, skip: Int) async throws -> [Commit] {
        let sep = Self.fieldSeparator
        let format = "%H\(sep)%s\(sep)%an\(sep)%aI\(sep)%P"
        // `--end-of-options` keeps a `-`-leading branch name from being parsed as a git
        // flag (defensive: branch values reach this public port from outside ZeusGit).
        let output = try runGit(
            ["log", "--format=\(format)", "-n", String(limit), "--skip", String(skip),
             "--end-of-options", branch],
            in: repo)
        return parseCommits(output)
    }

    public func diff(forCommit sha: String, in repo: URL) async throws -> CommitDiff {
        let numstat = try runGit(["show", "--numstat", "--format=", "--end-of-options", sha], in: repo)
        let nameStatus = try runGit(["show", "--name-status", "--format=", "--end-of-options", sha], in: repo)
        let patch = try runGit(["show", "--format=", "--end-of-options", sha], in: repo)
        return CommitDiff(sha: sha,
                          files: parseFileChanges(numstat: numstat, nameStatus: nameStatus),
                          patch: patch)
    }

    public func status(at url: URL) async throws -> GitStatus {
        parseStatus(try runGit(["status", "--porcelain=v2", "--branch"], in: url))
    }

    /// Collapses `git status --porcelain=v2 --branch` into one overall status.
    /// Precedence (most-actionable first): uncommitted tracked changes → `.dirty`,
    /// else new untracked files → `.untracked`, else local commits ahead of upstream
    /// → `.ahead` (diverged counts as ahead), else `.behind`, else `.clean`.
    /// In v2, `1`/`2` are changed/renamed tracked entries, `u` is unmerged, `?` is
    /// untracked, and `# branch.ab +A -B` carries the ahead/behind counts.
    func parseStatus(_ output: String) -> GitStatus {
        var ahead = 0, behind = 0
        var hasTrackedChanges = false
        var hasUntracked = false

        for raw in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(raw)
            if line.hasPrefix("# branch.ab ") {
                (ahead, behind) = parseAheadBehind(line)
            } else if line.hasPrefix("1 ") || line.hasPrefix("2 ") || line.hasPrefix("u ") {
                hasTrackedChanges = true
            } else if line.hasPrefix("? ") {
                hasUntracked = true
            }
        }

        if hasTrackedChanges { return .dirty }
        if hasUntracked { return .untracked }
        if ahead > 0 { return .ahead }
        if behind > 0 { return .behind }
        return .clean
    }

    /// Extracts the counts from a `# branch.ab +A -B` line (signed tokens, any order).
    private func parseAheadBehind(_ line: String) -> (ahead: Int, behind: Int) {
        var ahead = 0, behind = 0
        for token in line.split(separator: " ") {
            if token.hasPrefix("+") { ahead = Int(token.dropFirst()) ?? 0 }
            else if token.hasPrefix("-") { behind = Int(token.dropFirst()) ?? 0 }
        }
        return (ahead, behind)
    }

    /// Joins `git show --numstat` (line counts) with `--name-status` (A/M/D) by path,
    /// preserving numstat order. Binary `-` counts become 0; renames map to the new path.
    func parseFileChanges(numstat: String, nameStatus: String) -> [FileChange] {
        var counts: [String: (Int, Int)] = [:]
        var order: [String] = []
        for line in numstat.split(separator: "\n") {
            let fields = String(line).components(separatedBy: "\t")
            guard fields.count >= 3 else { continue }
            let path = fields[fields.count - 1]
            counts[path] = (Int(fields[0]) ?? 0, Int(fields[1]) ?? 0)
            order.append(path)
        }

        var statuses: [String: FileStatus] = [:]
        for line in nameStatus.split(separator: "\n") {
            let fields = String(line).components(separatedBy: "\t")
            guard let code = fields.first?.first, let path = fields.last, fields.count >= 2 else { continue }
            statuses[path] = Self.fileStatus(code)
        }

        return order.map { path in
            let (additions, deletions) = counts[path] ?? (0, 0)
            return FileChange(path: path, status: statuses[path] ?? .modified,
                              additions: additions, deletions: deletions)
        }
    }

    private static func fileStatus(_ code: Character) -> FileStatus {
        switch code {
        case "A": return .added
        case "D": return .deleted
        default:  return .modified
        }
    }

    /// `git for-each-ref` args producing tab-separated local-branch rows (see `parseBranches`).
    private var branchRefArgs: [String] {
        ["for-each-ref",
         "--format=%(refname:short)\t%(HEAD)\t%(upstream:short)\t%(upstream:track)",
         "refs/heads"]
    }

    /// Parses `git worktree list --porcelain`. The first worktree block is the main checkout.
    func parseWorktrees(_ porcelain: String) -> [Worktree] {
        var result: [Worktree] = []
        var path: URL?
        var branch: String?
        var locked = false

        func flush() {
            guard let current = path else { return }
            let branches = branch.map { [Branch(name: $0, isCurrent: true)] } ?? []
            result.append(Worktree(path: current, isMain: result.isEmpty, isLocked: locked, branches: branches))
            path = nil; branch = nil; locked = false
        }

        for raw in porcelain.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.isEmpty { flush(); continue }
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            switch parts.first {
            case "worktree": path = URL(fileURLWithPath: parts.count > 1 ? parts[1] : "")
            case "branch":   branch = parts.count > 1 ? parts[1].replacingOccurrences(of: "refs/heads/", with: "") : nil
            case "locked":   locked = true
            default:         break
            }
        }
        flush()
        return result
    }

    /// Parses tab-separated `git for-each-ref` output for local branches.
    /// Format: `%(refname:short)\t%(HEAD)\t%(upstream:short)\t%(upstream:track)`.
    func parseBranches(_ output: String) -> [Branch] {
        output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { raw in
            let fields = String(raw).components(separatedBy: "\t")
            guard let name = fields.first, !name.isEmpty else { return nil }
            let isCurrent = fields.count > 1 && fields[1].trimmingCharacters(in: .whitespaces) == "*"
            let upstream = fields.count > 2 && !fields[2].isEmpty ? fields[2] : nil
            let (ahead, behind) = parseTrack(fields.count > 3 ? fields[3] : "")
            return Branch(name: name, isCurrent: isCurrent, upstream: upstream, ahead: ahead, behind: behind)
        }
    }

    /// Extracts ahead/behind counts from a `%(upstream:track)` value like `[ahead 1, behind 2]`.
    private func parseTrack(_ track: String) -> (ahead: Int, behind: Int) {
        func count(after keyword: String) -> Int {
            guard let range = track.range(of: keyword) else { return 0 }
            return Int(track[range.upperBound...].prefix { $0.isNumber }) ?? 0
        }
        return (count(after: "ahead "), count(after: "behind "))
    }

    /// Parses unit-separated (0x1f) `git log` output. Format: `%H%x1f%s%x1f%an%x1f%aI%x1f%P`,
    /// one commit per line. `%aI` is strict ISO 8601; `%P` is a space-separated parent list.
    func parseCommits(_ output: String) -> [Commit] {
        let formatter = ISO8601DateFormatter()
        return output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { raw in
            let fields = String(raw).components(separatedBy: Self.fieldSeparator)
            guard fields.count == 5, !fields[0].isEmpty else { return nil }
            let date = formatter.date(from: fields[3]) ?? Date(timeIntervalSince1970: 0)
            let parents = fields[4].split(separator: " ").map(String.init)
            return Commit(id: fields[0], summary: fields[1], authorName: fields[2],
                          date: date, parents: parents)
        }
    }

    /// `git --version` — used as a lightweight availability check / smoke test.
    public func version() throws -> String {
        try runGit(["--version"], in: URL(fileURLWithPath: NSTemporaryDirectory()))
    }

    @discardableResult
    func runGit(_ args: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        process.currentDirectoryURL = directory
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }
}
