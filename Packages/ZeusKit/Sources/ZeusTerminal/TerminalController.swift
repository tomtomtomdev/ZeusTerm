import Foundation
import ZeusDomain

/// The narrow slice of a live terminal view the controller writes user input into.
/// SwiftTerm's `LocalProcessTerminalView` satisfies this via its `send(txt:)` (the conformance
/// lives in `TerminalEmulatorView`, which imports SwiftTerm); tests substitute a spy.
@MainActor
public protocol TerminalInputSink: AnyObject {
    /// Inject `text` into the PTY as if the user typed it.
    func send(txt: String)
}

/// Bridges the `TerminalSessionControlling` port to a live SwiftTerm PTY: `send(_:)` writes
/// the text into the terminal (feature #6, and the target of right-arrow accept — §2.4). The
/// view doesn't exist when the controller is created, so the sink is bound later via `attach(_:)`.
@MainActor
public final class TerminalController: TerminalSessionControlling {
    public let workingDirectory: URL
    private weak var sink: TerminalInputSink?
    /// Text sent before the view was bound, replayed in order once `attach(_:)` happens.
    private var pending: [String] = []

    public init(workingDirectory: URL) {
        self.workingDirectory = workingDirectory
    }

    /// Bind the live terminal view once it's been created, flushing anything queued before it existed.
    public func attach(_ sink: TerminalInputSink) {
        self.sink = sink
        for text in pending { sink.send(txt: text) }
        pending.removeAll()
    }

    public func send(_ text: String) {
        if let sink {
            sink.send(txt: text)
        } else {
            pending.append(text)
        }
    }
}
