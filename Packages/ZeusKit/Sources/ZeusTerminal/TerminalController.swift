import Foundation
import ZeusDomain

/// Placeholder terminal session. The real PTY (SwiftTerm `LocalProcessTerminalView`)
/// is wired in the S1 spike / P5 (SPEC §2.6). For now it records sent text for tests.
public final class TerminalController: TerminalSessionControlling {
    public let workingDirectory: URL
    public private(set) var sentText: [String] = []

    public init(workingDirectory: URL) {
        self.workingDirectory = workingDirectory
    }

    public func send(_ text: String) {
        sentText.append(text)
    }
}
