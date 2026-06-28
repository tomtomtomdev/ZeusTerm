import Foundation
import ZeusDomain

/// Command autosuggestions for the right-arrow accept feature (#4).
/// Ranks history by frecency, then falls back to git-subcommand knowledge; filesystem
/// path completion lands later in P6.
public struct SuggestionEngine: SuggestionProviding {
    private let history: [String]

    public init(history: [String] = []) {
        self.history = history
    }

    /// Common git subcommands, suggested on `git <prefix>` even when absent from history.
    private static let gitSubcommands = [
        "add", "branch", "checkout", "cherry-pick", "clone", "commit", "config",
        "diff", "fetch", "init", "log", "merge", "pull", "push", "rebase",
        "remote", "reset", "restore", "revert", "stash", "status", "switch", "tag", "worktree",
    ]

    private static func gitSubcommandMatches(for input: String) -> [String] {
        gitSubcommands
            .map { "git \($0)" }
            .filter { $0.hasPrefix(input) && $0 != input }
    }

    /// Commands whose argument is a filesystem path — only these trigger path completion,
    /// so a bare/`git` command's argument is never mistaken for a path.
    private static let pathTakingCommands: Set<String> = [
        "cd", "ls", "cat", "less", "more", "vim", "vi", "nano", "code", "open",
        "rm", "cp", "mv", "touch", "mkdir", "rmdir", "pushd", "source",
    ]

    /// Completes the argument being typed against the entries in `cwd`, when the command
    /// is one that takes a path. Returns full command lines (typed prefix + matched entry).
    private static func pathCompletions(for input: String, cwd: URL) -> [String] {
        guard let lastSpace = input.lastIndex(of: " "),
              let commandEnd = input.firstIndex(of: " ") else { return [] }
        guard pathTakingCommands.contains(String(input[..<commandEnd])) else { return [] }

        let prefix = String(input[...lastSpace])                    // typed text up to + incl. last space
        let fragment = String(input[input.index(after: lastSpace)...])  // the partial path being typed
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: cwd.path)) ?? []
        return entries
            .filter { $0.hasPrefix(fragment) }
            .sorted()
            .map { prefix + $0 }
    }

    /// A history command that prefix-matched the input, with the signals frecency ranks on.
    private struct Candidate {
        let command: String
        var frequency: Int
        var recency: Int   // most-recent position in history; later = more recent
    }

    public func suggestions(for input: String, cwd: URL) async -> [String] {
        guard !input.isEmpty else { return [] }

        // Tally each matching command's use count and most-recent position in history
        // (history is oldest→newest, so a later index means a more recent use).
        var candidates: [String: Candidate] = [:]
        for (index, command) in history.enumerated() where command.hasPrefix(input) && command != input {
            var candidate = candidates[command] ?? Candidate(command: command, frequency: 0, recency: index)
            candidate.frequency += 1
            candidate.recency = index
            candidates[command] = candidate
        }

        // Rank history by frecency: more frequent first, ties broken by the more recent use.
        let ranked = candidates.values.sorted { lhs, rhs in
            lhs.frequency != rhs.frequency ? lhs.frequency > rhs.frequency : lhs.recency > rhs.recency
        }

        // Sources in precedence order; the combiner keeps the first occurrence of each.
        return Self.merged([
            ranked.map(\.command),                       // shell history, frecency-ranked
            Self.gitSubcommandMatches(for: input),       // git subcommand knowledge
            Self.pathCompletions(for: input, cwd: cwd),  // filesystem path completion
        ])
    }

    /// Concatenates the source lists in order, keeping only the first occurrence of each command.
    private static func merged(_ sources: [[String]]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for command in sources.joined() where seen.insert(command).inserted {
            result.append(command)
        }
        return result
    }
}
