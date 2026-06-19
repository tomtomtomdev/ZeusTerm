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
}
