import SwiftUI
import AppKit
import ZeusDomain

/// The app-managed suggestion input line — SPEC §2.4's *headline* approach, validated by spike S2
/// and now wired into the terminal panel (P6, feature #4). A borderless monospaced field shows the
/// typed command with dimmed **ghost text** of the best suggestion; `→` at end-of-line accepts it
/// (otherwise it's an ordinary cursor move — the SPEC §12 #5 guardrail), and `Enter` commits the
/// typed line to the terminal session (the running shell).
///
/// Depends only on `SuggestionStore` (suggestion-line state) and the `TerminalSessionControlling`
/// port (to inject the committed command + read the cwd for path completions) — no SwiftTerm import,
/// so the dependency rule holds. Key interception + PTY injection are /verify-gated (proven by S2);
/// the accept/submit logic underneath is unit-tested in `SuggestionStoreTests`.
@MainActor
public struct SuggestionInputLine: View {
    private let store: SuggestionStore
    private let session: any TerminalSessionControlling
    private let theme: Theme

    public init(store: SuggestionStore, session: any TerminalSessionControlling, theme: Theme) {
        self.store = store
        self.session = session
        self.theme = theme
    }

    private let fontSize: CGFloat = 13
    /// Borderless NSTextField has a small intrinsic left text inset; nudge the ghost layer to match
    /// so the dimmed suggestion lands exactly after the typed text (monospaced ⇒ equal advances).
    private let ghostLeadingInset: CGFloat = 4

    public var body: some View {
        ZStack(alignment: .leading) {
            // Ghost layer (behind): the typed text in clear reserves the width, the suggestion's
            // tail shows dimmed. Reads store.line ⇒ re-renders when a query resolves.
            HStack(spacing: 0) {
                Text(store.line.input).foregroundStyle(.clear)
                Text(store.line.ghostText).foregroundStyle(theme.textDim)
                Spacer(minLength: 0)
            }
            .font(.system(size: fontSize, design: .monospaced))
            .padding(.leading, ghostLeadingInset)
            .allowsHitTesting(false)

            GhostField(store: store, session: session, theme: theme, fontSize: fontSize)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(theme.control)
        .overlay(theme.hairline.frame(height: 1), alignment: .top)   // hairline above the terminal
    }
}

/// Borderless single-line NSTextField bridged into SwiftUI. The Coordinator intercepts `→`
/// (accept-at-EOL only) and `Enter` (commit → terminal session); the dimmed ghost is drawn by the
/// SwiftUI overlay behind this transparent field.
private struct GhostField: NSViewRepresentable {
    let store: SuggestionStore
    let session: any TerminalSessionControlling
    let theme: Theme
    let fontSize: CGFloat

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        field.textColor = NSColor(theme.textHi)
        field.placeholderString = "Run a command — → accepts the suggestion, Enter runs it"
        field.delegate = context.coordinator
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.lineBreakMode = .byClipping
        // Make the caret + system text legible on the dark panel.
        if theme == .dark { field.appearance = NSAppearance(named: .darkAqua) }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(store: store, session: session) }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        private let store: SuggestionStore
        private let session: any TerminalSessionControlling

        init(store: SuggestionStore, session: any TerminalSessionControlling) {
            self.store = store
            self.session = session
        }

        // Keystroke → re-query the engine for the new input + caret, against the session's cwd.
        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            store.update(input: field.stringValue,
                         caret: caretCharIndex(in: field),
                         cwd: session.workingDirectory)
        }

        // Intercept editing commands before the field editor handles them.
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveRight(_:)):
                // EOL guardrail: accept only when the caret is genuinely at end-of-line. Gate on the
                // LIVE field-editor caret, not store state — arrow/mouse caret moves don't fire
                // controlTextDidChange, so store.line.caret can be stale.
                let text = textView.string as NSString
                let selection = textView.selectedRange()
                let atEnd = selection.length == 0 && selection.location == text.length
                guard atEnd, let completed = store.accept() else {
                    return false   // mid-line → let `→` move the cursor as usual
                }
                textView.string = completed
                let end = (completed as NSString).length
                textView.setSelectedRange(NSRange(location: end, length: 0))
                return true        // consumed: no cursor move

            case #selector(NSResponder.insertNewline(_:)):
                guard let command = store.submit() else { return true }   // empty line: send nothing
                session.send(command + "\r")                              // commit to the PTY
                textView.string = ""
                return true

            default:
                return false
            }
        }

        /// Caret position as a Character count (matching `SuggestionLine.caret`'s units), derived from
        /// the field editor's UTF-16 selection location.
        private func caretCharIndex(in field: NSTextField) -> Int {
            guard let editor = field.currentEditor() else { return field.stringValue.count }
            let text = field.stringValue as NSString
            let location = min(editor.selectedRange.location, text.length)
            return text.substring(to: location).count
        }
    }
}
