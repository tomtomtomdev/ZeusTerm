import Foundation

/// Reads the user's zsh history file and parses it into the command list that seeds
/// `SuggestionEngine`'s frecency ranking. Read-only and best-effort: any failure to read
/// (missing file, no permission) degrades to an empty list rather than blocking suggestions.
public struct ShellHistoryReader {
    private let parser = ShellHistoryParser()
    private let maxEntries: Int

    /// - Parameter maxEntries: how many of the most-recent commands to keep, so a huge
    ///   history file doesn't bloat the engine. The newest entries are the file's tail.
    public init(maxEntries: Int = 2000) {
        self.maxEntries = maxEntries
    }

    /// Reads + parses the history file at `url`, keeping the most-recent `maxEntries`;
    /// returns [] if it can't be read. Decodes leniently — real histories carry non-UTF-8 bytes
    /// (accented paths, zsh-metafied chars), so invalid sequences become U+FFFD rather than
    /// failing the whole read and dropping every suggestion.
    public func history(at url: URL) -> [String] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let contents = String(decoding: data, as: UTF8.self)
        return Array(parser.commands(from: contents).suffix(maxEntries))
    }

    /// Resolves the zsh history file location: an exported `$HISTFILE` if present (absolute or
    /// `~/`-relative to `home`), else the stock `~/.zsh_history`. `HISTFILE` is usually a shell
    /// variable that zsh doesn't export, so the default is what applies in practice.
    public static func defaultHistoryURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        guard let histfile = environment["HISTFILE"], !histfile.isEmpty else {
            return home.appendingPathComponent(".zsh_history")
        }
        if histfile.hasPrefix("/") { return URL(fileURLWithPath: histfile) }
        let relative = histfile.hasPrefix("~/") ? String(histfile.dropFirst(2)) : histfile
        return home.appendingPathComponent(relative)
    }
}
