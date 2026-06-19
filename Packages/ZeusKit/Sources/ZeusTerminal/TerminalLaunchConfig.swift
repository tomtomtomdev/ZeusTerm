import Foundation

/// Pure resolution of how to launch a PTY shell session: which shell, argv[0],
/// the environment, and the working directory. Kept framework-free and unit-tested
/// so the SwiftTerm-bound view (`TerminalEmulatorView`) only has to *apply* it.
public struct TerminalLaunchConfig: Equatable, Sendable {
    /// Absolute path to the shell binary (e.g. `/bin/zsh`).
    public let executable: String
    /// argv[0] for the process. A leading `-` makes it a login shell (`-zsh`).
    public let execName: String?
    /// Environment passed to the child, forcing 256-color + truecolor support.
    public let environment: [String: String]
    /// Directory the shell starts in.
    public let currentDirectory: String

    /// Environment formatted as `["KEY=VALUE", ...]`, sorted for determinism —
    /// the shape SwiftTerm's `startProcess(environment:)` expects.
    public var environmentList: [String] {
        environment.map { "\($0.key)=\($0.value)" }.sorted()
    }

    public static func resolve(
        workingDirectory: URL,
        environment: [String: String]
    ) -> TerminalLaunchConfig {
        let shell = environment["SHELL"] ?? "/bin/zsh"
        let shellName = (shell as NSString).lastPathComponent

        var env = environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"

        return TerminalLaunchConfig(
            executable: shell,
            execName: "-\(shellName)",
            environment: env,
            currentDirectory: workingDirectory.path
        )
    }
}
