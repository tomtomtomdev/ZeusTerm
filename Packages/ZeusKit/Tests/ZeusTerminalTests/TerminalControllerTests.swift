import Testing
import Foundation
@testable import ZeusTerminal

/// Spy standing in for the live `LocalProcessTerminalView` — records every text
/// injection the controller forwards, so we can assert the send→PTY bridge without a real PTY.
@MainActor
private final class SpyInputSink: TerminalInputSink {
    private(set) var injected: [String] = []
    func send(txt: String) { injected.append(txt) }
}

@MainActor
struct TerminalControllerTests {

    private let cwd = URL(fileURLWithPath: "/Users/me/Projects/app", isDirectory: true)

    @Test func sendForwardsToAttachedSink() {
        let controller = TerminalController(workingDirectory: cwd)
        let sink = SpyInputSink()
        controller.attach(sink)

        controller.send("ls -la\n")

        #expect(sink.injected == ["ls -la\n"])
    }

    @Test func textSentBeforeAttachFlushesInOrderOnAttach() {
        let controller = TerminalController(workingDirectory: cwd)
        controller.send("echo one\n")
        controller.send("echo two\n")

        let sink = SpyInputSink()
        controller.attach(sink)

        #expect(sink.injected == ["echo one\n", "echo two\n"])
    }

    @Test func flushedTextIsNotReplayedForLaterSends() {
        let controller = TerminalController(workingDirectory: cwd)
        controller.send("before\n")

        let sink = SpyInputSink()
        controller.attach(sink)
        controller.send("after\n")

        // "before" flushes exactly once on attach; the live send appends only "after".
        #expect(sink.injected == ["before\n", "after\n"])
    }
}
