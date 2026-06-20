import Foundation
import GRDB
import ZeusDomain

/// GRDB/SQLite-backed `RepositoryIndexStore` (P3-D.2, SPEC §167/§188). Persists one row per
/// discovered repo so cold start can paint the hub before a rescan, and so rescans only touch
/// what changed. GRDB lives only in this adapter — the domain sees the pure `IndexEntry` DTO.
/// `lastScanned` is stored as a Unix timestamp (Double) for stable, locale-free ordering.
public struct GRDBRepositoryIndexStore: RepositoryIndexStore {
    private let dbQueue: DatabaseQueue

    /// File-backed index at `path` (the app's on-disk index location). Creates the schema if
    /// the file is new.
    public init(path: String) throws {
        try self.init(dbQueue: DatabaseQueue(path: path))
    }

    /// In-memory index — used by tests, and a safe fallback when no file path is available.
    public init() throws {
        try self.init(dbQueue: DatabaseQueue())
    }

    private init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        try dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS repo_index (
                    path TEXT PRIMARY KEY NOT NULL,
                    head_sha TEXT,
                    last_scanned DOUBLE NOT NULL
                )
                """)
        }
    }

    public func load() async throws -> [IndexEntry] {
        try await dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT path, head_sha, last_scanned FROM repo_index ORDER BY path")
                .map { row in
                    IndexEntry(path: row["path"],
                               headSHA: row["head_sha"],
                               lastScanned: Date(timeIntervalSince1970: row["last_scanned"]))
                }
        }
    }

    public func upsert(_ entries: [IndexEntry]) async throws {
        guard !entries.isEmpty else { return }
        try await dbQueue.write { db in
            for entry in entries {
                try db.execute(sql: """
                    INSERT INTO repo_index (path, head_sha, last_scanned)
                    VALUES (?, ?, ?)
                    ON CONFLICT(path) DO UPDATE SET
                        head_sha = excluded.head_sha,
                        last_scanned = excluded.last_scanned
                    """,
                    arguments: [entry.path, entry.headSHA, entry.lastScanned.timeIntervalSince1970])
            }
        }
    }

    public func remove(paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        try await dbQueue.write { db in
            let placeholders = Array(repeating: "?", count: paths.count).joined(separator: ",")
            try db.execute(sql: "DELETE FROM repo_index WHERE path IN (\(placeholders))",
                           arguments: StatementArguments(paths))
        }
    }
}
