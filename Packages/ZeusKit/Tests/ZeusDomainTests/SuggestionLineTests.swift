import Testing
@testable import ZeusDomain

struct SuggestionLineTests {

    @Test func ghostTextIsTheSuggestionBeyondTheTypedInput() {
        let line = SuggestionLine(input: "git pu", suggestion: "git push", caret: 6)
        #expect(line.ghostText == "sh")
    }

    @Test func acceptsOnlyWhenCaretIsAtEndOfLine() {
        let atEnd = SuggestionLine(input: "git pu", suggestion: "git push", caret: 6)
        #expect(atEnd.canAccept)

        // Caret in the middle of the line — '→' should move the cursor, not accept.
        let midLine = SuggestionLine(input: "git pu", suggestion: "git push", caret: 3)
        #expect(!midLine.canAccept)
    }

    @Test func acceptingReplacesTheLineWithTheFullSuggestion() {
        let line = SuggestionLine(input: "git pu", suggestion: "git push", caret: 6)
        #expect(line.accepted == "git push")
    }

    @Test func withoutGhostTextThereIsNothingToAcceptAndTheLineIsUnchanged() {
        // Caret at EOL but the suggestion exactly equals the input → no ghost, no accept.
        let exact = SuggestionLine(input: "git push", suggestion: "git push", caret: 8)
        #expect(exact.ghostText.isEmpty)
        #expect(!exact.canAccept)
        #expect(exact.accepted == "git push")

        // No suggestion at all → accepting is a no-op.
        let none = SuggestionLine(input: "ls", suggestion: nil, caret: 2)
        #expect(!none.canAccept)
        #expect(none.accepted == "ls")
    }
}
