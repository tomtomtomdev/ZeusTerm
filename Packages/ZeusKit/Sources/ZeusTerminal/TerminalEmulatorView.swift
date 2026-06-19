import SwiftUI
import SwiftTerm

/// SwiftUI bridge for SwiftTerm's `LocalProcessTerminalView` — a real PTY hosting a
/// login shell. This is the S1 spike's "prove it runs" surface (SPEC §4): resize reflow
/// and truecolor are SwiftTerm's job, so this stays thin. Evolves into the P5 session view.
///
/// Note: the host app must be **non-sandboxed** for the shell to access the filesystem
/// (Zeus v1 ships Developer ID + non-sandboxed — SPEC §8).
public struct TerminalEmulatorView: NSViewRepresentable {
    private let config: TerminalLaunchConfig

    /// Launch with an explicit, pre-resolved config (used by tests/harness).
    public init(config: TerminalLaunchConfig) {
        self.config = config
    }

    /// Launch a login shell in `workingDirectory`, inheriting the current environment.
    public init(workingDirectory: URL) {
        self.config = TerminalLaunchConfig.resolve(
            workingDirectory: workingDirectory,
            environment: ProcessInfo.processInfo.environment
        )
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
