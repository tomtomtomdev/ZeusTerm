import Foundation
import Observation
import ZeusDomain

/// Drives the right-arrow autocomplete (feature #4, SPEC §2.4): it mirrors the user's keystrokes
/// into a `PromptLineEditor`, asks the `SuggestionProviding` engine for the best match against the
/// current line, and publishes a `SuggestionLine` the terminal overlay renders as dimmed ghost text.
/// Accepting (`→` at end-of-line) writes the ghost into the live PTY via `TerminalSessionControlling`.
///
/// The shell stays the source of truth for the line's *contents*; this only models Zeus's view of it
/// for suggestion purposes. Each edit supersedes any in-flight fetch (like the other stores) so a
/// slower earlier lookup can't clobber the suggestion for what's now on screen.
@MainActor
@Observable
public final class PromptSuggestionStore {
    /// The current line + best suggestion, ready for the overlay to render ghost text and gate `→`.
    public private(set) var line = SuggestionLine(input: "", suggestion: nil, caret: 0)

    @ObservationIgnored private let engine: SuggestionProviding
    @ObservationIgnored private let terminal: TerminalSessionControlling
    @ObservationIgnored private var editor = PromptLineEditor()
    @ObservationIgnored private var suggestTask: Task<Void, Never>?

    public init(engine: SuggestionProviding, terminal: TerminalSessionControlling) {
        self.engine = engine
        self.terminal = terminal
    }

    deinit { suggestTask?.cancel() }

    /// Mirrors typed text into the editor and refreshes the suggestion for the new line.
    public func type(_ text: String) {
        editor.type(text)
        refresh()
    }

    /// Mirrors a backspace and refreshes the suggestion for the now-shorter line.
    public func backspace() {
        editor.backspace()
        refresh()
    }

    /// Mirrors `←`: only the caret moves, so the suggestion stands but the accept gate re-evaluates
    /// (a caret off end-of-line disables `→` accept — SPEC §2.4). No new fetch; the input is unchanged.
    public func moveLeft() {
        editor.moveLeft()
        republishForCaret()
    }

    /// Mirrors `→` as a cursor move (used when it isn't accepting): re-evaluates the accept gate for
    /// the new caret without refetching.
    public func moveRight() {
        editor.moveRight()
        republishForCaret()
    }

    /// Republishes the line after a caret-only change: keeps the current suggestion, but `canAccept`
    /// recomputes against the new caret. No fetch — the typed input is unchanged.
    private func republishForCaret() {
        line = editor.suggestionLine(with: line.suggestion)
    }

    /// Accepts the current suggestion when `→` is pressed at end-of-line: writes just the ghost text
    /// (the chars beyond what's typed) into the PTY — the typed prefix is already in the shell — and
    /// extends the mirrored line to the full suggestion. A no-op returning `false` when there's
    /// nothing to accept, so the caller lets `→` fall through as an ordinary cursor move.
    @discardableResult
    public func acceptSuggestion() -> Bool {
        guard line.canAccept else { return false }
        let ghost = line.ghostText
        terminal.send(ghost)
        editor.type(ghost)
        refresh()
        return true
    }

    /// The command was submitted (Enter) or the line otherwise cleared: cancels any in-flight fetch
    /// and resets to an empty line so no stale ghost lingers into the next prompt.
    public func submit() {
        suggestTask?.cancel()
        editor.submit()
        line = editor.suggestionLine(with: nil)
    }

    /// Test seam: await the in-flight suggestion fetch (no-op if none), mirroring the other stores.
    public func waitForSuggestion() async { await suggestTask?.value }

    /// Republishes the current line with no suggestion, then fetches the best match for it off-main;
    /// the result is applied only if the line hasn't changed since (last-requested wins).
    private func refresh() {
        suggestTask?.cancel()
        line = editor.suggestionLine(with: nil)
        let input = editor.input
        let cwd = terminal.workingDirectory
        suggestTask = Task { [weak self] in
            let results = await self?.engine.suggestions(for: input, cwd: cwd) ?? []
            guard let self, !Task.isCancelled, self.editor.input == input else { return }
            self.line = self.editor.suggestionLine(with: results.first)
        }
    }
}
