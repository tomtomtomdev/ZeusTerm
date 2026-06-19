import Testing
import Foundation
@testable import ZeusTerminal

struct TerminalLaunchConfigTests {

    private let cwd = URL(fileURLWithPath: "/Users/me/Projects/app", isDirectory: true)

    @Test func usesShellFromEnvironment() {
        let config = TerminalLaunchConfig.resolve(
            workingDirectory: cwd,
            environment: ["SHELL": "/opt/homebrew/bin/fish"]
        )
        #expect(config.executable == "/opt/homebrew/bin/fish")
    }

    @Test func fallsBackToZshWhenShellAbsent() {
        let config = TerminalLaunchConfig.resolve(workingDirectory: cwd, environment: [:])
        #expect(config.executable == "/bin/zsh")
    }

    @Test func launchesAsLoginShellViaDashArgv0() {
        // Convention: a leading "-" on argv[0] makes the shell a login shell.
        let config = TerminalLaunchConfig.resolve(
            workingDirectory: cwd,
            environment: ["SHELL": "/bin/zsh"]
        )
        #expect(config.execName == "-zsh")
    }

    @Test func forces256ColorTerm() {
        let config = TerminalLaunchConfig.resolve(workingDirectory: cwd, environment: [:])
        #expect(config.environment["TERM"] == "xterm-256color")
    }

    @Test func forcesTruecolor() {
        let config = TerminalLaunchConfig.resolve(workingDirectory: cwd, environment: [:])
        #expect(config.environment["COLORTERM"] == "truecolor")
    }

    @Test func preservesInheritedEnvironment() {
        let config = TerminalLaunchConfig.resolve(
            workingDirectory: cwd,
            environment: ["PATH": "/usr/bin", "HOME": "/Users/me"]
        )
        #expect(config.environment["PATH"] == "/usr/bin")
        #expect(config.environment["HOME"] == "/Users/me")
    }

    @Test func passesThroughWorkingDirectory() {
        let config = TerminalLaunchConfig.resolve(workingDirectory: cwd, environment: [:])
        #expect(config.currentDirectory == "/Users/me/Projects/app")
    }

    @Test func environmentListIsSortedKeyValueStrings() {
        let config = TerminalLaunchConfig.resolve(
            workingDirectory: cwd,
            environment: ["SHELL": "/bin/zsh"]
        )
        // SwiftTerm's startProcess(environment:) wants ["KEY=VALUE", ...].
        #expect(config.environmentList.contains("TERM=xterm-256color"))
        #expect(config.environmentList.contains("COLORTERM=truecolor"))
        #expect(config.environmentList == config.environmentList.sorted())
    }
}
