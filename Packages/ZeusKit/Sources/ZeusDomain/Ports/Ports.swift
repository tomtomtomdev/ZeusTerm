import Foundation

// Ports (protocols) the domain depends on. Adapters in ZeusGit / ZeusScanner /
// ZeusTerminal / ZeusSuggest / the app implement these. Dependencies point inward.

/// Discovers candidate git repositories on disk (feature #1).
public protocol ProjectScanning: Sendable {
    /// Returns directory URLs that contain a `.git` entry, under the given roots.
    func discoverRepositoryURLs(under roots: [URL]) async throws -> [URL]
}

/// Reads git model data for a repository (feature #2).
public protocol GitReading: Sendable {
    func readRepository(at url: URL) async throws -> Repository
}

/// Provides command autosuggestions for the right-arrow accept feature (#4).
public protocol SuggestionProviding: Sendable {
    func suggestions(for input: String, cwd: URL) async -> [String]
}

/// Drives a live terminal session (feature #6). Reference type, UI-bound — not Sendable.
public protocol TerminalSessionControlling: AnyObject {
    var workingDirectory: URL { get }
    func send(_ text: String)
}

/// Loads and persists `ZeusSettings` (gradient/theme, feature #7).
public protocol SettingsStoring: Sendable {
    func load() throws -> ZeusSettings
    func save(_ settings: ZeusSettings) throws
}
