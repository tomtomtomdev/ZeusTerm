import Testing
import Foundation
@testable import ZeusSuggest

struct SuggestionEngineTests {

    @Test func returnsRecentDedupedPrefixMatches() async {
        let engine = SuggestionEngine(history: ["git status", "git stash", "git status", "ls"])
        let suggestions = await engine.suggestions(for: "git st", cwd: URL(fileURLWithPath: "/"))

        #expect(suggestions.first == "git status") // most-recent first, deduped
        #expect(suggestions.contains("git stash"))
        #expect(!suggestions.contains("ls"))
    }

    @Test func emptyInputYieldsNoSuggestions() async {
        let engine = SuggestionEngine(history: ["git status"])
        let suggestions = await engine.suggestions(for: "", cwd: URL(fileURLWithPath: "/"))
        #expect(suggestions.isEmpty)
    }

    @Test func ranksByFrecencyFrequentBeatsMoreRecentButRare() async {
        // "git push" used 3×, "git pull" used once and more recently. Pure recency
        // would surface "git pull" first; frecency must put the frequent one on top.
        let engine = SuggestionEngine(history: ["git push", "git push", "git push", "git pull"])
        let suggestions = await engine.suggestions(for: "git p", cwd: URL(fileURLWithPath: "/"))

        #expect(suggestions.first == "git push")
        #expect(suggestions == ["git push", "git pull"])
    }

    @Test func frecencyTieBreaksByRecencyWhenFrequencyIsEqual() async {
        // Both used twice; "git push" was used most recently, so it wins the tie.
        let engine = SuggestionEngine(history: ["git pull", "git push", "git pull", "git push"])
        let suggestions = await engine.suggestions(for: "git p", cwd: URL(fileURLWithPath: "/"))

        #expect(suggestions == ["git push", "git pull"])
    }

    @Test func suggestsKnownGitSubcommandsAbsentFromHistory() async {
        // No history at all — git subcommand knowledge alone should answer "git c".
        let engine = SuggestionEngine(history: [])
        let suggestions = await engine.suggestions(for: "git c", cwd: URL(fileURLWithPath: "/"))

        #expect(suggestions.contains("git commit"))
        #expect(suggestions.contains("git checkout"))
    }

    @Test func completesPathsForPathTakingCommandsAgainstCwd() async throws {
        // A controlled cwd holding three entries; "cd Do" should complete to the two
        // that share the "Do" prefix and not the one that doesn't.
        let fm = FileManager.default
        let cwd = fm.temporaryDirectory.appendingPathComponent("zeus-suggest-\(UUID().uuidString)")
        try fm.createDirectory(at: cwd, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: cwd) }
        for name in ["Documents", "Downloads", "Desktop"] {
            try fm.createDirectory(at: cwd.appendingPathComponent(name), withIntermediateDirectories: true)
        }

        let engine = SuggestionEngine(history: [])
        let suggestions = await engine.suggestions(for: "cd Do", cwd: cwd)

        #expect(suggestions.contains("cd Documents"))
        #expect(suggestions.contains("cd Downloads"))
        #expect(!suggestions.contains("cd Desktop"))
    }

    @Test func historyLeadsGitSubcommandsAndCrossSourceDuplicatesCollapse() async {
        // "git status" is in history (so it leads), git knowledge also offers it (must not
        // duplicate) plus "git stash"/"git switch" which fill in behind, in knowledge order.
        let engine = SuggestionEngine(history: ["git status", "git status"])
        let suggestions = await engine.suggestions(for: "git s", cwd: URL(fileURLWithPath: "/"))

        #expect(suggestions == ["git status", "git stash", "git switch"])
    }
}
