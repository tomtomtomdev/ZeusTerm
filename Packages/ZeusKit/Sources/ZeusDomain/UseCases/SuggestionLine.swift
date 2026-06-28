import Foundation

/// Pure model of the right-arrow autocomplete input line (feature #4, SPEC §2.4).
/// Holds what the user has typed, the current best suggestion, and the caret position,
/// and derives the dimmed **ghost text** plus whether `→` may accept it. The accept gate
/// honors the guardrail: only accept when the caret sits at end-of-line.
public struct SuggestionLine: Sendable, Equatable {
    public let input: String
    public let suggestion: String?
    /// Caret position as a count of `Character`s from the start of `input` (NOT a UTF-16
    /// offset) — end-of-line is `caret == input.count`. UI callers must convert accordingly.
    public let caret: Int

    public init(input: String, suggestion: String?, caret: Int) {
        self.input = input
        self.suggestion = suggestion
        self.caret = caret
    }

    /// The portion of the suggestion beyond what's typed, shown dimmed after the caret.
    /// Empty when there is no suggestion or it doesn't extend the typed input.
    public var ghostText: String {
        guard let suggestion, suggestion.hasPrefix(input) else { return "" }
        return String(suggestion.dropFirst(input.count))
    }

    /// Whether pressing `→` accepts the suggestion: only when the caret is at end-of-line
    /// and there is ghost text to accept (otherwise `→` is an ordinary cursor move).
    public var canAccept: Bool {
        caret == input.count && !ghostText.isEmpty
    }

    /// The line after accepting: the typed text extended by the ghost (i.e. the full
    /// suggestion). When there is nothing to accept, the line is returned unchanged.
    public var accepted: String {
        canAccept ? input + ghostText : input
    }
}
