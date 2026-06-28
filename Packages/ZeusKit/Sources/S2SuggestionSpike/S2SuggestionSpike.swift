import AppKit
import Foundation
import SwiftUI
import SwiftTerm
import ZeusDomain
import ZeusSuggest
import ZeusTerminal
import ZeusUI

// =============================================================================
// S2 SPIKE (SPEC §4) — Right-arrow accept.
//
// Question: can we render ghost text + accept on `→` and inject to the PTY cleanly?
// Acceptance: type a partial command, `→` completes it, `Enter` runs it.
//
// This proves SPEC §2.4's *headline* approach — an app-managed suggestion line (a
// custom input editor that renders the typed command + dimmed ghost; `→` at EOL
// accepts; the committed line is written to the PTY). It exercises the already-unit-
// tested SuggestionLine / SuggestionStore logic through real AppKit key events and a
// real SwiftTerm PTY.
//
// THROWAWAY SPIKE — TDD-exempt per CLAUDE.md ("Exceptions: throwaway spikes in §4 of
// SPEC … default is always TDD"). The accept/EOL/ghost LOGIC is covered by
// SuggestionLineTests + SuggestionStoreTests; what's new here (NSTextField `→`
// interception, send-to-PTY) is inherently /verify-gated — PTY + key events can't be
// asserted in-process.
//
//   swift run S2SuggestionSpike             # interactive — ghost line above a live PTY
//   swift run S2SuggestionSpike --selftest  # headless: accept → inject → assert it RAN (auto)
//   swift run S2SuggestionSpike --keytest   # input line only (no terminal) — isolates →/Enter
//
// Verification status (see SPEC §4 outcomes): --selftest PASSES autonomously, proving
// engine→ghost→accept→inject→executed against a real store + real SwiftTerm PTY. The literal
// `→` keypress (moveRight: → the handler below) is the /verify-by-human step — GUI keystroke
// automation isn't reliable on this machine (window opens on a separate Space). When run by
// hand, every keystroke / accept / submit prints an `S2-KEY …` line to stderr.
// =============================================================================

@main
struct S2SuggestionSpike {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let cwd = FileManager.default.homeDirectoryForCurrentUser
        let store = SuggestionStore(engine: SuggestionEngine(history: SpikeData.history))
        let bridge = PTYBridge()
        let selftest = CommandLine.arguments.contains("--selftest")
        let keytest = CommandLine.arguments.contains("--keytest")

        let root = S2SpikeView(store: store, bridge: bridge, cwd: cwd, showTerminal: !keytest)
            .frame(minWidth: 900, minHeight: 600)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Zeus — S2 Right-Arrow Accept Spike"
        window.contentViewController = NSHostingController(rootView: root)
        window.center()

        let delegate = AppDelegate(window: window, store: store, bridge: bridge, cwd: cwd, selftest: selftest)
        app.delegate = delegate
        app.run()
    }
}

// MARK: - App lifecycle

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let window: NSWindow
    private let store: SuggestionStore
    private let bridge: PTYBridge
    private let cwd: URL
    private let selftest: Bool

    init(window: NSWindow, store: SuggestionStore, bridge: PTYBridge, cwd: URL, selftest: Bool) {
        self.window = window
        self.store = store
        self.bridge = bridge
        self.cwd = cwd
        self.selftest = selftest
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if selftest { runSelfTest() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Headless acceptance check for the parts we CAN automate: ghost → accept → inject → ran.
    /// (The literal `→` keypress is manual-verify; here we call the same store.accept() the key
    /// handler calls, then the same bridge.run() the Enter handler calls.)
    private func runSelfTest() {
        let store = store, bridge = bridge, cwd = cwd
        Task { @MainActor in
            func emit(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

            try? await Task.sleep(for: .seconds(1.0))   // let the login shell boot + draw a prompt

            // 1) Type a partial command; the engine suggests the seeded marker command.
            let partial = "echo S2"
            store.update(input: partial, caret: partial.count, cwd: cwd)
            await store.waitForLoad()
            let ghost = store.line.ghostText

            // 2) `→` accept (same call the key handler makes).
            let accepted = store.accept()
            let expected = "echo S2_OK_$((6*7))"
            let acceptOK = (accepted == expected)
            emit("S2-SELFTEST ghost=\(ghost.debugDescription) accepted=\(accepted.debugDescription) acceptOK=\(acceptOK)")

            // 3) `Enter` → inject the committed line into the real PTY (same call the Enter handler makes).
            bridge.run(accepted ?? "")
            try? await Task.sleep(for: .seconds(1.5))    // let zsh evaluate + echo output

            // 4) The shell can only produce "S2_OK_42" by EXECUTING `echo S2_OK_$((6*7))` —
            //    the echoed *input* line contains the literal "$((6*7))", never "42".
            let out = bridge.capturedText()
            let ran = out.contains("S2_OK_42")
            emit("S2-SELFTEST ran=\(ran)")
            emit("S2-SELFTEST-RESULT \((acceptOK && ran) ? "PASS" : "FAIL")")
            exit((acceptOK && ran) ? 0 : 1)
        }
    }
}

// MARK: - PTY bridge (send a committed line into the shell; read its buffer)

/// Holds the live terminal view so the input line can inject a command, and the selftest
/// can read back what the shell printed.
@MainActor
final class PTYBridge {
    fileprivate weak var view: LocalProcessTerminalView?

    /// Write the committed command to the child shell as if Enter was pressed (`\r`).
    func run(_ command: String) {
        view?.send(txt: command + "\r")
    }

    /// The full visible grid as text — used only by --selftest to confirm a command ran.
    func capturedText() -> String {
        guard let view else { return "" }
        let terminal = view.getTerminal()
        let dims = terminal.getDims()
        guard dims.cols > 0, dims.rows > 0 else { return "" }
        return terminal.getText(
            start: Position(col: 0, row: 0),
            end: Position(col: dims.cols - 1, row: dims.rows - 1)
        )
    }
}

// MARK: - SwiftUI shell

private struct S2SpikeView: View {
    let store: SuggestionStore
    let bridge: PTYBridge
    let cwd: URL
    /// `--keytest` renders the input line alone (no terminal) to isolate `→`/Enter routing
    /// from terminal focus competition.
    var showTerminal: Bool = true

    /// Borderless NSTextField has a small intrinsic left text inset; nudge the ghost layer
    /// to match so the dimmed suggestion lands exactly after the typed text (monospaced).
    private let ghostLeadingInset: CGFloat = 4
    private let fontSize: CGFloat = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            inputCard
            if showTerminal {
                SpikeTerminalView(bridge: bridge, cwd: cwd)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(.white.opacity(0.12))
                    )
            } else {
                Spacer()
            }
        }
        .padding(18)
        .background(Color(red: 0.04, green: 0.05, blue: 0.08).ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("S2 — Right-arrow accept", systemImage: "arrow.right.to.line.compact")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Type below (focus is the app line, not the terminal). e.g. `git pu` → dimmed `sh` → press → to accept → Enter runs it in the shell. Move the caret left with ← then press → : it only moves the cursor (no accept) — the EOL guardrail.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var inputCard: some View {
        ZStack(alignment: .leading) {
            // Ghost layer (behind): typed text in clear reserves the width, ghost shown dimmed.
            HStack(spacing: 0) {
                Text(store.line.input).foregroundStyle(.clear)
                Text(store.line.ghostText).foregroundStyle(.white.opacity(0.34))
                Spacer(minLength: 0)
            }
            .font(.system(size: fontSize, design: .monospaced))
            .padding(.leading, ghostLeadingInset)
            .allowsHitTesting(false)

            GhostInputField(store: store, cwd: cwd, fontSize: fontSize) { submitted in
                bridge.run(submitted)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white.opacity(0.14)))
    }
}

// MARK: - Ghost input field (app-managed suggestion line)

/// Borderless single-line NSTextField wired to the SuggestionStore. The Coordinator
/// intercepts `→` (accept-at-EOL only) and `Enter` (commit → PTY); the dimmed ghost is
/// drawn by the SwiftUI overlay behind this transparent field.
private struct GhostInputField: NSViewRepresentable {
    let store: SuggestionStore
    let cwd: URL
    let fontSize: CGFloat
    let onSubmit: (String) -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = FocusGrabbingTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        field.textColor = .white
        field.placeholderString = "type a command — → accepts, Enter runs"
        field.delegate = context.coordinator
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.lineBreakMode = .byClipping
        DispatchQueue.main.async { [weak field] in field?.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(store: store, cwd: cwd, onSubmit: onSubmit) }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        private let store: SuggestionStore
        private let cwd: URL
        private let onSubmit: (String) -> Void

        init(store: SuggestionStore, cwd: URL, onSubmit: @escaping (String) -> Void) {
            self.store = store
            self.cwd = cwd
            self.onSubmit = onSubmit
        }

        // Keystroke → re-query the engine for the new input + caret.
        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            let caret = caretCharIndex(in: field)
            Self.log("change=\(field.stringValue.debugDescription) caret=\(caret)")  // spike instrumentation
            store.update(input: field.stringValue, caret: caret, cwd: cwd)
        }

        // Intercept editing commands before the field editor handles them.
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveRight(_:)):
                // EOL guardrail: only accept when the caret is genuinely at end-of-line.
                // Gate on the LIVE field-editor caret, not store state — arrow/mouse caret
                // moves don't fire controlTextDidChange, so store.line.caret can be stale.
                let text = textView.string as NSString
                let selection = textView.selectedRange()
                let atEnd = selection.length == 0 && selection.location == text.length
                guard atEnd, let completed = store.accept() else {
                    return false   // mid-line → let `→` move the cursor as usual
                }
                textView.string = completed
                let end = (completed as NSString).length
                textView.setSelectedRange(NSRange(location: end, length: 0))
                Self.log("accept=\(completed.debugDescription)")   // spike instrumentation
                return true        // consumed: no cursor move

            case #selector(NSResponder.insertNewline(_:)):
                let command = textView.string
                guard !command.isEmpty else { return true }
                Self.log("submit=\(command.debugDescription)")     // spike instrumentation
                onSubmit(command)                       // write committed line to the PTY
                textView.string = ""
                store.update(input: "", caret: 0, cwd: cwd)
                return true

            default:
                return false
            }
        }

        /// Spike instrumentation: lets the headless key-driven check (osascript → stderr) confirm
        /// a *physical* `→`/Enter actually routed through this handler.
        private static func log(_ message: String) {
            FileHandle.standardError.write(Data(("S2-KEY " + message + "\n").utf8))
        }

        /// Caret position as a Character count (matching SuggestionLine.caret's units),
        /// derived from the field editor's UTF-16 selection location.
        private func caretCharIndex(in field: NSTextField) -> Int {
            guard let editor = field.currentEditor() else { return field.stringValue.count }
            let text = field.stringValue as NSString
            let location = min(editor.selectedRange.location, text.length)
            return text.substring(to: location).count
        }
    }
}

/// Claims first responder as soon as it's in a window, so the app-managed line is focused
/// on launch (no click needed) and wins focus over the terminal view.
private final class FocusGrabbingTextField: NSTextField {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { window?.makeFirstResponder(self) }
    }
}

// MARK: - Terminal (live PTY, registers with the bridge)

private struct SpikeTerminalView: NSViewRepresentable {
    let bridge: PTYBridge
    let cwd: URL

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 880, height: 380))
        let config = TerminalLaunchConfig.resolve(
            workingDirectory: cwd,
            environment: ProcessInfo.processInfo.environment
        )
        view.processDelegate = context.coordinator
        view.startProcess(
            executable: config.executable,
            args: [],
            environment: config.environmentList,
            execName: config.execName,
            currentDirectory: config.currentDirectory
        )
        bridge.view = view
        return view
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func processTerminated(source: TerminalView, exitCode: Int32?) {}
    }
}

// MARK: - Seeded history (so suggestions appear without a real shell-history reader)

private enum SpikeData {
    /// Frecency-biased so the demos are crisp: `git s`→status, `git pu`→push, `swift b`→build.
    /// `echo S2_OK_$((6*7))` is the --selftest marker (also harmless in interactive use).
    static let history: [String] = [
        "git status", "git status", "git status",
        "git push", "git push",
        "git pull",
        "git commit -m \"wip\"",
        "git checkout main",
        "git log --oneline",
        "git diff",
        "swift build", "swift build",
        "swift test",
        "swift run S1TerminalSpike",
        "xcodebuild -scheme Zeus build",
        "ls -la", "ls",
        "cd Desktop", "cd Documents",
        "clear",
        "echo S2_OK_$((6*7))",
    ]
}
