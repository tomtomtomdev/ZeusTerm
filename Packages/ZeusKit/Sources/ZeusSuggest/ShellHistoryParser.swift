import Foundation

/// Parses the contents of a zsh history file into a list of commands, oldest→newest
/// (the file's natural append order, which is exactly what `SuggestionEngine`'s frecency
/// ranking expects). Pure and side-effect-free; `ShellHistoryReader` handles the I/O.
public struct ShellHistoryParser {
    public init() {}

    /// Folds physical lines into logical entries (joining backslash-continued multi-line
    /// commands), strips the EXTENDED_HISTORY metadata prefix, and drops blanks.
    public func commands(from contents: String) -> [String] {
        var entries: [String] = []
        var pending: String?   // accumulates a backslash-continued entry across physical lines
        for physical in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(physical)
            let entry = pending.map { $0 + "\n" + line } ?? line
            if entry.hasSuffix("\\") {
                pending = String(entry.dropLast())  // escaped newline → keep accumulating
            } else {
                pending = nil
                entries.append(entry)
            }
        }
        if let pending { entries.append(pending) }   // file ended mid-continuation

        return entries
            .map { Self.stripMetadata(from: $0) }
            .filter { !$0.isEmpty }
    }

    /// EXTENDED_HISTORY lines look like ": <start>:<elapsed>;<command>". When a line has that
    /// shape, return just the command; otherwise return the line unchanged (plain history).
    private static func stripMetadata(from line: String) -> String {
        guard line.hasPrefix(": "),
              let semicolon = line.firstIndex(of: ";") else { return line }
        let metadata = line[line.index(line.startIndex, offsetBy: 2)..<semicolon]
        guard metadata.contains(":"), metadata.allSatisfy({ $0.isNumber || $0 == ":" }) else {
            return line
        }
        return String(line[line.index(after: semicolon)...])
    }
}
