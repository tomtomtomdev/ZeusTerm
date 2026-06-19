import AppKit
import SwiftUI
import ZeusUI
import ZeusTerminal

// S1 spike harness (SPEC §4) — a throwaway GUI app proving SwiftTerm gives us a real,
// resizable PTY in SwiftUI. Run it, then exercise the acceptance criteria by hand:
//   - run `vim`, `htop`, `claude`
//   - resize the window → content reflows
//   - truecolor renders (try: `printf '\e[38;2;255;100;0mTRUECOLOR\e[0m\n'`)
//
// Not a unit test — PTY interactivity can't be asserted in-process; we observe it.
@main
struct S1TerminalSpike {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let cwd = FileManager.default.homeDirectoryForCurrentUser
        let root = AppShellView {
            TerminalEmulatorView(workingDirectory: cwd)
        }
        .frame(minWidth: 1000, minHeight: 640)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Zeus — S1 Terminal Spike"
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
