import Foundation
import SwiftTerm
import ZeusDomain

/// Adapter implementing the domain's `TerminalSessionControlling` port over SwiftTerm's
/// `LocalProcessTerminalView`. It's the seam the app-managed suggestion line writes committed
/// commands through (S2 → P6): the input line accepts a ghost on `→`, commits on Enter, and calls
/// `send(_:)` to inject the line into the running shell's stdin.
///
/// The PTY view is created by `TerminalEmulatorView.makeNSView` and handed here via `attach(_:)`,
/// so the session can outlive SwiftUI's struct-view churn while still reaching the live view.
/// `send` is a no-op until attached (nothing to write to yet).
///
/// `workingDirectory` is the shell's launch directory for now; live `cd` tracking (OSC 7 via the
/// terminal delegate) is a follow-up refinement — until then path completions resolve against the
/// launch dir, while history/git suggestions are unaffected.
@MainActor
public final class TerminalSession: TerminalSessionControlling {
    public let workingDirectory: URL
    private weak var view: LocalProcessTerminalView?

    public init(workingDirectory: URL) {
        self.workingDirectory = workingDirectory
    }

    /// Connect the live PTY view once it exists. Called from `TerminalEmulatorView.makeNSView`.
    func attach(_ view: LocalProcessTerminalView) {
        self.view = view
    }

    /// Write text to the child shell's stdin (the committed command should include its own newline).
    /// No-op until a view is attached.
    public func send(_ text: String) {
        view?.send(txt: text)
    }
}
