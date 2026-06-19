import Foundation
import ZeusDomain

/// Reads git data by shelling out to the `git` CLI. Worktree enumeration goes through
/// `git worktree list --porcelain` (libgit2's worktree bindings are thin — see SPEC §5).
/// P0 implements worktree discovery; branch/commit reads are filled in P2.
public struct GitCLIService: GitReading {
    public init() {}

    public func readRepository(at url: URL) async throws -> Repository {
        let top = try runGit(["rev-parse", "--show-toplevel"], in: url)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let root = URL(fileURLWithPath: top.isEmpty ? url.path : top)
        let worktrees = parseWorktrees(try runGit(["worktree", "list", "--porcelain"], in: root))
        return Repository(name: root.lastPathComponent, commonDir: root, worktrees: worktrees)
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
