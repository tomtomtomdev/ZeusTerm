import Testing
import Foundation
@testable import ZeusSuggest

struct ShellHistoryReaderTests {

    /// Writes `contents` to a unique temp file and hands its URL to `body`, cleaning up after.
    private func withHistoryFile(_ contents: String, _ body: (URL) throws -> Void) throws {
        let fm = FileManager.default
        let url = fm.temporaryDirectory.appendingPathComponent("zeus-hist-\(UUID().uuidString)")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(at: url) }
        try body(url)
    }

    @Test func readsAndParsesAHistoryFile() throws {
        try withHistoryFile(": 1:0;git status\n: 2:0;ls\n") { url in
            let reader = ShellHistoryReader()
            #expect(reader.history(at: url) == ["git status", "ls"])
        }
    }

    @Test func invalidUTF8BytesDoNotWipeTheWholeHistory() throws {
        // Real zsh histories carry non-UTF-8 bytes (accented paths, zsh-metafied chars). A strict
        // decode would return nil for the whole file; a later valid command must still survive.
        let fm = FileManager.default
        let url = fm.temporaryDirectory.appendingPathComponent("zeus-hist-\(UUID().uuidString)")
        var data = Data([0xFF, 0xFE])                       // invalid UTF-8 on the first line
        data.append(Data("\nls -la\n".utf8))
        try data.write(to: url)
        defer { try? fm.removeItem(at: url) }

        #expect(ShellHistoryReader().history(at: url).contains("ls -la"))
    }

    @Test func missingFileDegradesToEmpty() {
        let reader = ShellHistoryReader()
        let absent = URL(fileURLWithPath: "/nonexistent/zeus-\(UUID().uuidString)/.zsh_history")
        #expect(reader.history(at: absent).isEmpty)
    }

    @Test func keepsOnlyTheMostRecentEntriesWhenCapped() throws {
        // A long history must not be loaded whole; only the newest `maxEntries` are kept,
        // and the file's tail is the most recent (oldest→newest append order).
        let lines = (1...10).map { "cmd\($0)" }.joined(separator: "\n") + "\n"
        try withHistoryFile(lines) { url in
            let reader = ShellHistoryReader(maxEntries: 3)
            #expect(reader.history(at: url) == ["cmd8", "cmd9", "cmd10"])
        }
    }

    @Test func defaultsToZshHistoryInHomeWhenHistfileUnset() {
        let home = URL(fileURLWithPath: "/Users/zeus")
        let url = ShellHistoryReader.defaultHistoryURL(environment: [:], home: home)
        #expect(url == home.appendingPathComponent(".zsh_history"))
    }

    @Test func honorsExportedHistfileEnvironmentVariable() {
        let url = ShellHistoryReader.defaultHistoryURL(
            environment: ["HISTFILE": "/custom/dir/.history"],
            home: URL(fileURLWithPath: "/Users/zeus"))
        #expect(url == URL(fileURLWithPath: "/custom/dir/.history"))
    }
}
