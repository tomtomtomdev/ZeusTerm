import Foundation

// Ports (protocols) the domain depends on. Adapters in ZeusGit / ZeusScanner /
// ZeusTerminal / ZeusSuggest / the app implement these. Dependencies point inward.

/// Discovers candidate git repositories on disk (feature #1).
public protocol ProjectScanning: Sendable {
    /// Returns directory URLs that contain a `.git` entry, under the given roots.
    func discoverRepositoryURLs(under roots: [URL]) async throws -> [URL]

    /// Names of the direct children of a repo directory (a shallow, non-recursive
    /// listing) — the marker files `RepoClassifier` matches on to type a repo (P3, §7).
    func rootEntryNames(at repo: URL) throws -> Set<String>
}

/// Reads git model data for a repository (feature #2).
public protocol GitReading: Sendable {
    func readRepository(at url: URL) async throws -> Repository

    /// Commits reachable from `branch`, newest first. Paginated and lazy —
    /// callers page on scroll; the full history is never walked eagerly (SPEC §2.2).
    func commits(forBranch branch: String, in repo: URL, limit: Int, skip: Int) async throws -> [Commit]

    /// Changed files + unified diff for a commit — drives the branch-tree Changes panel (§7).
    func diff(forCommit sha: String, in repo: URL) async throws -> CommitDiff

    /// A single overall working-tree status for a repo — drives constellation node
    /// fill (P3, §7). One status per repo; see the adapter for the precedence rule.
    func status(at url: URL) async throws -> GitStatus

    /// Current HEAD commit sha, or nil when HEAD points at no commit yet. Cheap
    /// change-detection for the incremental rescan (P3-D): the planner compares this
    /// against the cached `IndexEntry.headSHA` to decide reuse vs refresh.
    func headSHA(at url: URL) async throws -> String?
}

/// Persists the scan index (SPEC §188) so cold start is instant and rescans are incremental
/// (P3-D). The domain owns this contract; the GRDB/SQLite adapter (P3-D.2) implements it.
/// Reconciliation logic stays pure in `IncrementalRescanPlanner` — this port is just I/O.
public protocol RepositoryIndexStore: Sendable {
    /// Every previously-indexed repo. Read once on cold start to paint the hub before rescanning.
    func load() async throws -> [IndexEntry]

    /// Insert-or-update the given entries by `path` (new repos + ones whose HEAD moved).
    func upsert(_ entries: [IndexEntry]) async throws

    /// Drop the index rows for these repo paths (repos that vanished from disk).
    func remove(paths: [String]) async throws
}

/// Watches the scan roots for filesystem changes so the Hub stays live (P3-D.3) — a new repo
/// appears, one vanishes, a commit moves HEAD, or a working-tree edit flips a repo's status,
/// all without the user relaunching. The FSEvents adapter (P3-D.3b) implements this; the store
/// (P3-D.3c) filters the stream through `ChangeRelevance` and debounces it before re-scanning.
public protocol FileSystemWatching: Sendable {
    /// An async stream of changed filesystem paths under `roots`. The adapter coalesces FSEvents
    /// at the OS latency window; the stream finishes (and the adapter tears down its FSEvents
    /// stream) when the task iterating it is cancelled.
    func changes(under roots: [URL]) -> AsyncStream<String>
}

/// Reports whether the app has Full Disk Access (P3-D, FDA hint). FSEvents live-refresh needs it on
/// TCC-protected roots; the pure `FullDiskAccessHint` rule turns this plus the watched roots into a
/// decision to nudge the user. The adapter (ZeusScanner) probes a TCC-gated path; no Apple API
/// reports the grant directly.
public protocol FullDiskAccessChecking: Sendable {
    func hasFullDiskAccess() -> Bool
}

/// Provides command autosuggestions for the right-arrow accept feature (#4).
public protocol SuggestionProviding: Sendable {
    func suggestions(for input: String, cwd: URL) async -> [String]
}

/// Drives a live terminal session (feature #6). Reference type, UI-bound — not Sendable;
/// main-actor isolated because it fronts an AppKit terminal view and PTY callbacks are
/// marshaled to main (SPEC §3).
@MainActor
public protocol TerminalSessionControlling: AnyObject {
    var workingDirectory: URL { get }
    func send(_ text: String)
}

/// Loads and persists `ZeusSettings` (gradient/theme, feature #7).
public protocol SettingsStoring: Sendable {
    func load() throws -> ZeusSettings
    func save(_ settings: ZeusSettings) throws
}
