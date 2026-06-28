import Testing
import Foundation
import ZeusDomain
@testable import ZeusUI

/// The UI-side store wiring the `SuggestionProviding` engine (off-main) to the pure
/// `SuggestionLine` model the input surface renders (ghost text + `→` accept, SPEC §2.4 / feature #4).
/// Same cancellable-single-task discipline as `CommitDiffStore` — a newer keystroke supersedes any
/// in-flight suggestion query. Tested with a stub `SuggestionProviding` — no engine, no disk.
@MainActor
struct SuggestionStoreTests {

    /// Returns the same canned suggestions for any input, ignoring cwd.
    private struct StubEngine: SuggestionProviding {
        let results: [String]
        init(_ results: [String]) { self.results = results }
        func suggestions(for input: String, cwd: URL) async -> [String] { results }
    }

    /// Suspends each `suggestions` call until `release(input:)` so a test can resolve queries out of
    /// order and prove a stale earlier query can't clobber a newer one. Actor-isolated state (matching
    /// the sibling `WorktreeOrbitStoreTests.Gate`) handles release-before-await without a lock.
    private actor GatedEngine: SuggestionProviding {
        private let results: [String: [String]]
        private var waiters: [String: CheckedContinuation<Void, Never>] = [:]
        private var released: Set<String> = []
        init(_ results: [String: [String]]) { self.results = results }

        func suggestions(for input: String, cwd: URL) async -> [String] {
            if !released.contains(input) {
                await withCheckedContinuation { waiters[input] = $0 }
            }
            return results[input] ?? []
        }

        func release(_ input: String) {
            released.insert(input)
            waiters.removeValue(forKey: input)?.resume()
        }
    }

    private let cwd = URL(fileURLWithPath: "/code/api")

    @Test func startsWithAnEmptyLine() {
        let store = SuggestionStore(engine: StubEngine([]))
        #expect(store.line == SuggestionLine(input: "", suggestion: nil, caret: 0))
        #expect(store.line.ghostText.isEmpty)
        #expect(store.line.canAccept == false)
    }

    @Test func typingPopulatesTheBestSuggestionAsGhostText() async {
        let store = SuggestionStore(engine: StubEngine(["git push"]))

        store.update(input: "git pu", caret: 6, cwd: cwd)
        await store.waitForLoad()

        #expect(store.line == SuggestionLine(input: "git pu", suggestion: "git push", caret: 6))
        #expect(store.line.ghostText == "sh")
        #expect(store.line.canAccept)
    }

    @Test func usesTheTopRankedSuggestionFromTheEngine() async {
        // The engine returns a frecency-ranked list; the store renders the first (best) one.
        let store = SuggestionStore(engine: StubEngine(["git status", "git stash"]))

        store.update(input: "git st", caret: 6, cwd: cwd)
        await store.waitForLoad()

        #expect(store.line.suggestion == "git status")
    }

    @Test func emptyInputClearsTheSuggestionWithoutQuerying() async {
        let store = SuggestionStore(engine: StubEngine(["git push"]))
        store.update(input: "git pu", caret: 6, cwd: cwd)
        await store.waitForLoad()
        #expect(store.line.suggestion != nil)                    // precondition: a suggestion is showing

        store.update(input: "", caret: 0, cwd: cwd)
        await store.waitForLoad()

        #expect(store.line == SuggestionLine(input: "", suggestion: nil, caret: 0))
        #expect(store.line.canAccept == false)
    }

    @Test func aNewKeystrokeClearsTheStaleSuggestionBeforeTheNewOneLoads() async {
        let store = SuggestionStore(engine: StubEngine(["git push"]))
        store.update(input: "git pu", caret: 6, cwd: cwd)
        await store.waitForLoad()
        #expect(store.line.ghostText == "sh")                    // a ghost is showing

        store.update(input: "git pus", caret: 7, cwd: cwd)
        // Cleared synchronously: the new typed text shows with no stale "sh" ghost lingering.
        #expect(store.line == SuggestionLine(input: "git pus", suggestion: nil, caret: 7))
        #expect(store.line.ghostText.isEmpty)

        await store.waitForLoad()
        #expect(store.line.suggestion == "git push")             // new query then fills it
    }

    @Test func acceptAtEndOfLineCompletesTheLineAndReturnsTheCommand() async {
        let store = SuggestionStore(engine: StubEngine(["git push"]))
        store.update(input: "git pu", caret: 6, cwd: cwd)
        await store.waitForLoad()
        #expect(store.line.canAccept)

        let accepted = store.accept()

        #expect(accepted == "git push")
        // Ghost consumed: the line now holds the full command, caret at its end, nothing left to accept.
        #expect(store.line == SuggestionLine(input: "git push", suggestion: nil, caret: 8))
        #expect(store.line.canAccept == false)
    }

    @Test func acceptIsANoOpWhenTheCaretIsNotAtEndOfLine() async {
        let store = SuggestionStore(engine: StubEngine(["git push"]))
        store.update(input: "git pu", caret: 3, cwd: cwd)                   // caret mid-line: `→` is an ordinary move
        await store.waitForLoad()
        #expect(store.line.canAccept == false)

        let accepted = store.accept()

        #expect(accepted == nil)
        #expect(store.line == SuggestionLine(input: "git pu", suggestion: "git push", caret: 3))
    }

    @Test func submitReturnsTheTypedLineAndResetsToEmpty() async {
        let store = SuggestionStore(engine: StubEngine(["git push"]))
        store.update(input: "git pu", caret: 6, cwd: cwd)
        await store.waitForLoad()

        let submitted = store.submit()                           // user pressed Enter

        #expect(submitted == "git pu")                           // runs what was typed, not the unaccepted ghost
        #expect(store.line == SuggestionLine(input: "", suggestion: nil, caret: 0))
    }

    @Test func submitOnAnEmptyLineReturnsNilAndChangesNothing() {
        let store = SuggestionStore(engine: StubEngine(["git push"]))

        let submitted = store.submit()                           // bare Enter at an empty prompt

        #expect(submitted == nil)                                // nothing to send to the PTY
        #expect(store.line == SuggestionLine(input: "", suggestion: nil, caret: 0))
    }

    @Test func submitAfterAcceptReturnsTheCompletedCommand() async {
        let store = SuggestionStore(engine: StubEngine(["git push"]))
        store.update(input: "git pu", caret: 6, cwd: cwd)
        await store.waitForLoad()
        _ = store.accept()                                       // `→` completed the line to "git push"

        let submitted = store.submit()                           // Enter runs the accepted command

        #expect(submitted == "git push")
        #expect(store.line == SuggestionLine(input: "", suggestion: nil, caret: 0))
    }

    @Test func submitCancelsAnInFlightQueryAndStaysCleared() async {
        let engine = GatedEngine(["git pu": ["git pull"]])
        let store = SuggestionStore(engine: engine)
        store.update(input: "git pu", caret: 6, cwd: cwd)        // query gated, still in flight

        let submitted = store.submit()                           // Enter before the suggestion resolves

        #expect(submitted == "git pu")
        #expect(store.line == SuggestionLine(input: "", suggestion: nil, caret: 0))

        await engine.release("git pu")                           // the stale query resolves late...
        await store.waitForLoad()
        #expect(store.line == SuggestionLine(input: "", suggestion: nil, caret: 0))  // ...and can't repopulate
    }

    @Test func aStaleEarlierQueryCannotClobberANewerKeystroke() async {
        let engine = GatedEngine(["git pu": ["git pull"], "git pus": ["git push"]])
        let store = SuggestionStore(engine: engine)

        store.update(input: "git pu", caret: 6, cwd: cwd)                  // query A — gated, then superseded
        store.update(input: "git pus", caret: 7, cwd: cwd)                 // query B — cancels A

        await engine.release("git pus")                                // B resolves first...
        await store.waitForLoad()                                // ...and is the awaited (live) task
        await engine.release("git pu")                                 // the stale A resolves late

        #expect(store.line.suggestion == "git push")             // B won; cancelled A never published
        #expect(store.line.input == "git pus")
    }
}
