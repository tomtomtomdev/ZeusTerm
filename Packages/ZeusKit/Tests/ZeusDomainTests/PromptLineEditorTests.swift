import Testing
@testable import ZeusDomain

struct PromptLineEditorTests {

    @Test func typingPrintableTextInsertsAtTheCaretAndAdvancesIt() {
        var editor = PromptLineEditor()
        editor.type("git")
        #expect(editor.input == "git")
        #expect(editor.caret == 3)
    }

    @Test func leftAndRightMoveTheCaretClampedToTheLineBounds() {
        var editor = PromptLineEditor()
        editor.type("git")            // caret == 3 (EOL)

        editor.moveLeft()
        #expect(editor.caret == 2)

        editor.moveLeft(); editor.moveLeft(); editor.moveLeft()  // clamps at 0
        #expect(editor.caret == 0)

        editor.moveRight()
        #expect(editor.caret == 1)

        editor.moveRight(); editor.moveRight(); editor.moveRight()  // clamps at input.count
        #expect(editor.caret == 3)
    }

    @Test func typingMidLineInsertsAtTheCaretNotTheEnd() {
        var editor = PromptLineEditor()
        editor.type("gt")
        editor.moveLeft()          // caret between 'g' and 't'
        editor.type("i")
        #expect(editor.input == "git")
        #expect(editor.caret == 2)
    }

    @Test func backspaceDeletesTheCharacterBeforeTheCaret() {
        var editor = PromptLineEditor()
        editor.type("git")
        editor.backspace()
        #expect(editor.input == "gi")
        #expect(editor.caret == 2)

        editor.moveLeft()          // caret between 'g' and 'i'
        editor.backspace()         // deletes 'g'
        #expect(editor.input == "i")
        #expect(editor.caret == 0)

        editor.backspace()         // at start of line — no-op
        #expect(editor.input == "i")
        #expect(editor.caret == 0)
    }

    @Test func submitClearsTheLineAndResetsTheCaret() {
        var editor = PromptLineEditor()
        editor.type("git status")
        editor.submit()
        #expect(editor.input == "")
        #expect(editor.caret == 0)
    }

    @Test func buildsASuggestionLineFromTheCurrentInputCaretAndSuggestion() {
        var editor = PromptLineEditor()
        editor.type("git pu")

        // At EOL, a matching suggestion yields acceptable ghost text.
        let atEnd = editor.suggestionLine(with: "git push")
        #expect(atEnd.ghostText == "sh")
        #expect(atEnd.canAccept)

        // Caret pulled off EOL: ghost still shows, but '→' must not accept.
        editor.moveLeft()
        let midLine = editor.suggestionLine(with: "git push")
        #expect(midLine.ghostText == "sh")
        #expect(!midLine.canAccept)
    }
}
