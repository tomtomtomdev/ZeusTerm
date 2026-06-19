import Foundation
import ZeusDomain

/// Command autosuggestions for the right-arrow accept feature (#4).
/// P0 ranks by recency from an injected history; filesystem + git-subcommand sources land in P6.
public struct SuggestionEngine: SuggestionProviding {
    private let history: [String]

    public init(history: [String] = []) {
        self.history = history
    }

    public func suggestions(for input: String, cwd: URL) async -> [String] {
        guard !input.isEmpty else { return [] }
        var seen = Set<String>()
        var result: [String] = []
        for command in history.reversed() where command.hasPrefix(input) && command != input {
            if seen.insert(command).inserted { result.append(command) }
        }
        return result
    }
}
