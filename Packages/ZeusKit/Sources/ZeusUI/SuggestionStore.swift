import Foundation
import Observation
import ZeusDomain

/// Drives the right-arrow autocomplete input surface (feature #4, SPEC §2.4): as the user types, it
/// queries the injected `SuggestionProviding` engine (off-main) for the current input + cwd and
/// publishes the pure `SuggestionLine` the surface renders (dimmed ghost text + the `→`-accept gate).
/// Depends only on the domain port — the concrete `SuggestionEngine` is injected at the composition
/// root, keeping the dependency rule intact.
///
/// Same cancellable-single-task discipline as `CommitDiffStore`: a newer keystroke clears any stale
/// suggestion up front and supersedes the in-flight query, so a slower earlier result can't clobber
/// a newer input.
@MainActor
@Observable
public final class SuggestionStore {
    /// What the input surface renders: the typed input, the best suggestion (if any), and the caret.
    public private(set) var line: SuggestionLine

    @ObservationIgnored private let engine: any SuggestionProviding
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    public init(engine: any SuggestionProviding) {
        self.engine = engine
        self.line = SuggestionLine(input: "", suggestion: nil, caret: 0)
    }

    deinit { loadTask?.cancel() }

    /// The user typed: query the engine off-main for the new input and publish the line with its best
    /// (highest-ranked) suggestion. `cwd` is supplied per call — the terminal's working directory
    /// changes with `cd`, so path completions must resolve against the *current* directory, never a
    /// value captured at construction. Cancels any in-flight query so a newer keystroke wins.
    public func update(input: String, caret: Int, cwd: URL) {
        loadTask?.cancel()
        line = SuggestionLine(input: input, suggestion: nil, caret: caret)  // clear stale ghost up front
        guard !input.isEmpty else { return }          // nothing typed: don't query
        loadTask = Task { [weak self] in
            guard let self else { return }
            let results = await self.engine.suggestions(for: input, cwd: cwd)
            if Task.isCancelled { return }
            self.line = SuggestionLine(input: input, suggestion: results.first, caret: caret)
        }
    }

    /// `→` was pressed. Accepts the suggestion only at end-of-line (the SPEC §2.4 / spike S2
    /// guardrail, enforced by `SuggestionLine.canAccept`): completes the line to the full suggestion
    /// — ghost consumed, caret at the end — and returns the command for the caller to inject into the
    /// PTY. Returns nil (and changes nothing) when there is nothing to accept, so the caller lets `→`
    /// act as an ordinary cursor move.
    @discardableResult
    public func accept() -> String? {
        guard line.canAccept else { return nil }
        let command = line.accepted
        loadTask?.cancel()                            // no late query repopulates the completed line
        line = SuggestionLine(input: command, suggestion: nil, caret: command.count)
        return command
    }

    /// Test seam: await the in-flight query (no-op if none), mirroring `CommitDiffStore.waitForLoad()`.
    public func waitForLoad() async { await loadTask?.value }
}
