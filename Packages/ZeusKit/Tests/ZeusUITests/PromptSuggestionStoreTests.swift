import Testing
import Foundation
import ZeusDomain
@testable import ZeusUI

/// The UI-side store for right-arrow autocomplete (feature #4, SPEC §2.4): it mirrors the user's
/// keystrokes into a `PromptLineEditor`, asks the `SuggestionProviding` engine for the best match
/// (off the current keystroke, superseding any in-flight fetch), and publishes a `SuggestionLine`
/// the terminal overlay renders as dimmed ghost text. Accepting (`→` at end-of-line) writes the
/// ghost into the live PTY via the `TerminalSessionControlling` port. Tested with a fake engine and
/// a spy terminal — no SwiftTerm, no PTY.
@MainActor
struct PromptSuggestionStoreTests {

    /// Canned suggestions keyed by the exact input they answer, so a stale fetch is distinguishable.
    private struct FakeEngine: SuggestionProviding {
        var byInput: [String: [String]] = [:]
        func suggestions(for input: String, cwd: URL) async -> [String] {
            byInput[input] ?? []
        }
    }

    /// Records every string written into the PTY (the accept target).
    private final class SpyTerminal: TerminalSessionControlling {
        let workingDirectory = URL(fileURLWithPath: "/code/api")
        private(set) var sent: [String] = []
        func send(_ text: String) { sent.append(text) }
    }

    /// Suspends the fetch for one input until the test opens the gate — forces a slow earlier
    /// lookup to resolve *after* a newer one, the out-of-order timing the supersede guard must beat.
    private actor Gate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var opened = false
        func wait() async {
            if opened { return }
            await withCheckedContinuation { continuation = $0 }
        }
        func open() {
            opened = true
            continuation?.resume()
            continuation = nil
        }
    }

    private struct GatedEngine: SuggestionProviding {
        var byInput: [String: [String]]
        var gate: Gate
        var gatedInput: String
        func suggestions(for input: String, cwd: URL) async -> [String] {
            if input == gatedInput { await gate.wait() }
            return byInput[input] ?? []
        }
    }

    @Test func typingResolvesTheTopSuggestionIntoGhostText() async {
        let engine = FakeEngine(byInput: ["git pu": ["git push", "git pull"]])
        let store = PromptSuggestionStore(engine: engine, terminal: SpyTerminal())

        store.type("git pu")
        await store.waitForSuggestion()

        #expect(store.line.input == "git pu")
        #expect(store.line.suggestion == "git push")
        #expect(store.line.ghostText == "sh")
    }

    @Test func acceptingAtEndOfLineWritesTheGhostIntoThePTYAndExtendsTheLine() async {
        let engine = FakeEngine(byInput: ["git pu": ["git push"]])
        let terminal = SpyTerminal()
        let store = PromptSuggestionStore(engine: engine, terminal: terminal)

        store.type("git pu")
        await store.waitForSuggestion()

        #expect(store.acceptSuggestion())          // caret at EOL, ghost present → accepts
        #expect(terminal.sent == ["sh"])           // only the ghost is injected; "git pu" is already in the shell
        #expect(store.line.input == "git push")    // mirror now holds the full command
        #expect(store.line.ghostText.isEmpty)      // nothing left to accept
    }

    @Test func acceptingWithNoGhostIsANoOpAndDoesNotTouchThePTY() async {
        let engine = FakeEngine()                  // no suggestions for anything
        let terminal = SpyTerminal()
        let store = PromptSuggestionStore(engine: engine, terminal: terminal)

        store.type("ls")
        await store.waitForSuggestion()

        #expect(!store.acceptSuggestion())         // nothing to accept → '→' is an ordinary cursor move
        #expect(terminal.sent.isEmpty)
        #expect(store.line.input == "ls")
    }

    @Test func aSlowEarlierFetchCannotClobberTheSuggestionForTheNewerLine() async {
        let gate = Gate()
        let engine = GatedEngine(byInput: ["gi": ["git status"], "git": ["git push"]],
                                 gate: gate, gatedInput: "gi")
        let store = PromptSuggestionStore(engine: engine, terminal: SpyTerminal())

        store.type("gi")                           // fetch for "gi" suspends on the gate
        store.type("t")                             // supersedes it; "git" is ungated
        await store.waitForSuggestion()             // awaits the latest (git)
        #expect(store.line.suggestion == "git push")

        await gate.open()                           // let the superseded "gi" fetch drain
        await Task.yield()
        #expect(store.line.suggestion == "git push")   // stale "gi" result did not clobber "git"
    }

    @Test func submitClearsTheLineForTheNextCommand() async {
        let engine = FakeEngine(byInput: ["git pu": ["git push"]])
        let store = PromptSuggestionStore(engine: engine, terminal: SpyTerminal())

        store.type("git pu")
        await store.waitForSuggestion()
        #expect(!store.line.ghostText.isEmpty)

        store.submit()
        #expect(store.line.input.isEmpty)
        #expect(store.line.suggestion == nil)
    }

    @Test func movingTheCaretOffEndOfLineDisablesAcceptButKeepsTheSuggestion() async {
        let engine = FakeEngine(byInput: ["git pu": ["git push"]])
        let terminal = SpyTerminal()
        let store = PromptSuggestionStore(engine: engine, terminal: terminal)

        store.type("git pu")
        await store.waitForSuggestion()

        store.moveLeft()                            // caret now mid-line
        #expect(store.line.suggestion == "git push")   // suggestion still shown...
        #expect(!store.acceptSuggestion())          // ...but '→' moves the cursor, doesn't accept
        #expect(terminal.sent.isEmpty)

        store.moveRight()                           // back to end-of-line
        #expect(store.acceptSuggestion())           // accept is enabled again
        #expect(terminal.sent == ["sh"])
    }

    @Test func backspaceMirrorsIntoTheLineAndRefreshesTheSuggestion() async {
        let engine = FakeEngine(byInput: ["git pu": ["git push"], "git p": ["git pull"]])
        let store = PromptSuggestionStore(engine: engine, terminal: SpyTerminal())

        store.type("git pu")
        await store.waitForSuggestion()
        #expect(store.line.suggestion == "git push")

        store.backspace()
        await store.waitForSuggestion()
        #expect(store.line.input == "git p")
        #expect(store.line.suggestion == "git pull")
    }
}
