import Foundation

/// Tracks what the user has typed on the current shell prompt line so the right-arrow
/// autocomplete (feature #4, SPEC §2.4) can suggest against it and know where the caret
/// sits. Zeus intercepts key input before it reaches the PTY and mirrors it here; the shell
/// remains the source of truth for the line's *contents*, this only models Zeus's view of it
/// for suggestion purposes. Caret is a `Character` offset (end-of-line is `caret == input.count`).
public struct PromptLineEditor: Sendable, Equatable {
    public private(set) var input: String = ""
    public private(set) var caret: Int = 0

    public init() {}

    /// The `String.Index` for the caret's `Character` offset.
    private var caretIndex: String.Index {
        input.index(input.startIndex, offsetBy: caret)
    }

    /// Inserts printable text at the caret and advances the caret past it.
    public mutating func type(_ text: String) {
        input.insert(contentsOf: text, at: caretIndex)
        caret += text.count
    }

    /// The current line paired with `suggestion`, ready for the UI to render ghost text and
    /// gate the `→` accept (accepts only at end-of-line — see `SuggestionLine`).
    public func suggestionLine(with suggestion: String?) -> SuggestionLine {
        SuggestionLine(input: input, suggestion: suggestion, caret: caret)
    }

    /// Resets to an empty line — the command was submitted (Enter) or the line otherwise cleared.
    public mutating func submit() {
        input = ""
        caret = 0
    }

    /// Deletes the character immediately before the caret; a no-op at the start of the line.
    public mutating func backspace() {
        guard caret > 0 else { return }
        caret -= 1
        input.remove(at: caretIndex)
    }

    /// Moves the caret one character left, clamped at the start of the line.
    public mutating func moveLeft() {
        caret = max(0, caret - 1)
    }

    /// Moves the caret one character right, clamped at end-of-line.
    public mutating func moveRight() {
        caret = min(input.count, caret + 1)
    }
}
