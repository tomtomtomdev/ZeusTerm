import Testing
@testable import ZeusSuggest

struct ShellHistoryParserTests {

    @Test func parsesPlainNewlineSeparatedCommandsInFileOrder() {
        let parser = ShellHistoryParser()
        let commands = parser.commands(from: "git status\nls -la\ncd ..\n")

        // File order is oldest→newest, exactly what the frecency engine expects.
        #expect(commands == ["git status", "ls -la", "cd .."])
    }

    @Test func stripsExtendedHistoryMetadataPrefix() {
        // EXTENDED_HISTORY writes ": <start-timestamp>:<elapsed-seconds>;<command>".
        let parser = ShellHistoryParser()
        let commands = parser.commands(from: ": 1700000000:0;git status\n: 1700000001:5;ls -la\n")

        #expect(commands == ["git status", "ls -la"])
    }

    @Test func joinsBackslashContinuedMultiLineEntries() {
        // zsh stores a multi-line command by escaping each embedded newline with a trailing "\".
        // The physical lines fold back into one entry; a following entry stays separate.
        let parser = ShellHistoryParser()
        let commands = parser.commands(from: ": 1:0;for i in 1 2\\\ndo echo $i\\\ndone\nls\n")

        #expect(commands == ["for i in 1 2\ndo echo $i\ndone", "ls"])
    }
}
