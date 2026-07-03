import SwiftUI
import SwiftTerm

/// SwiftUI bridge for SwiftTerm's `LocalProcessTerminalView` — a real PTY hosting a
/// login shell. This is the S1 spike's "prove it runs" surface (SPEC §4): resize reflow
/// and truecolor are SwiftTerm's job, so this stays thin. The P5 session view.
///
/// A `TerminalController` (the `TerminalSessionControlling` port) is attached to the live
/// view in `makeNSView`, giving the rest of the app a way to write into the PTY — this is
/// the target of right-arrow accept (SPEC §2.4: "the line is written to the PTY").
///
/// Note: the host app must be **non-sandboxed** for the shell to access the filesystem
/// (Zeus v1 ships Developer ID + non-sandboxed — SPEC §8).
public struct TerminalEmulatorView: NSViewRepresentable {
    private let controller: TerminalController
    private let config: TerminalLaunchConfig

    /// Launch a login shell for `controller.workingDirectory`; the controller is bound to the
    /// live view so `controller.send(_:)` writes into this PTY.
    public init(
        controller: TerminalController,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.controller = controller
        self.config = TerminalLaunchConfig.resolve(
            workingDirectory: controller.workingDirectory,
            environment: environment
        )
    }

    /// Convenience for callers that don't drive the PTY externally (spike/harness): opens a
    /// login shell in `workingDirectory` behind a private controller.
    public init(workingDirectory: URL) {
        self.init(controller: TerminalController(workingDirectory: workingDirectory))
    }

    public func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.processDelegate = context.coordinator
        view.startProcess(
            executable: config.executable,
            args: [],
            environment: config.environmentList,
            execName: config.execName,
            currentDirectory: config.currentDirectory
        )
        controller.attach(view)
        return view
    }

    public func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // SwiftTerm reflows on its own bounds changes; nothing to push from SwiftUI.
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    /// Minimal delegate so a shell exit (e.g. `exit`) doesn't go unobserved.
    public final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        public func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        public func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        public func processTerminated(source: TerminalView, exitCode: Int32?) {}
    }
}

/// SwiftTerm's terminal view already exposes `send(txt:)` (inject as if typed), so it satisfies
/// the controller's input seam directly — this is the only place SwiftTerm meets the port.
extension LocalProcessTerminalView: TerminalInputSink {}
