import AppKit
import SwiftUI
import ZeusUI
import ZeusTerminal

// P4 zoom-feel harness (roadmap item A.5) — a throwaway GUI app that mounts the full
// `ConstellationShell` over the sample data so the SPEC §7 powers-of-ten zoom can be felt
// and tuned by eye. The pure zoom math (`ZoomTransition`) and the state machine
// (`NavigationReducer`/`NavigationStore`) are already unit-tested; what *cannot* be asserted
// in-process is the motion's feel — easing, duration, and the opacity hand-off across a
// transition (flagged by `/code-review`). Run it, then exercise the acceptance criteria:
//
//   - Click a repo star on the Hub → it should zoom INTO that star (pivot on the clicked node)
//     and unfold the worktree orbits. Click a satellite → zoom into the branch tree.
//   - The ‹ Back pill and the topbar breadcrumb should zoom back OUT, pivoting on the node we
//     dived through (origins stack). Breadcrumb supports multi-level hops.
//   - Pointer events are dead while a transition is in flight (can't double-trigger mid-zoom).
//   - Toggle the sun/moon for the light theme. Enable System Settings ▸ Reduce Motion → dives
//     should switch INSTANTLY (no zoom).
//   - Watch the opacity hand-off: does the incoming level read as "unfolding from" the focal
//     node, or does it just blink in after a blank gap? (This is the feel we're tuning.)
//
// Not a unit test — a spike (SPEC §4 convention). Distinct from SPEC §4's "S2 = right-arrow
// accept"; this harness is purely about the §7 zoom motion.
@main
struct ZoomSpike {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let cwd = FileManager.default.homeDirectoryForCurrentUser
        // Inject a real PTY into the bottom panel so the harness doubles as a near-complete
        // preview of the app before item E wires the package into the Xcode target. Sample-backed
        // stores feed the constellation (no scan / git) so the harness is purely about zoom feel.
        let root = ConstellationShell<TerminalEmulatorView>.sample(theme: .dark) {
            TerminalEmulatorView(workingDirectory: cwd)
        }
        .frame(minWidth: 1200, minHeight: 800)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1320, height: 860),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Zeus — Zoom Spike (A.5)"
        window.contentViewController = NSHostingController(rootView: root)
        window.center()

        let delegate = AppDelegate(window: window)
        app.delegate = delegate
        app.run()
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let window: NSWindow

    init(window: NSWindow) {
        self.window = window
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
