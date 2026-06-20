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
        try Self.migrator.migrate(dbQueue)
    }

    /// Versioned schema, so each shipped column change has an explicit upgrade path.
    /// `v1` recreates the D.2b schema; it uses `IF NOT EXISTS` so a db that was created by that
    /// adapter *before* the migrator existed (and thus has no migration bookkeeping) is treated
    /// as already at v1 instead of erroring on a duplicate table. `v2` adds the rich payload with
    /// `NOT NULL DEFAULT`, which is what lets the ALTER backfill existing rows to neutral values.
    private static let migrator: DatabaseMigrator = {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_repo_index") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS repo_index (
                    path TEXT PRIMARY KEY NOT NULL,
                    head_sha TEXT,
                    last_scanned DOUBLE NOT NULL
                )
                """)
        }
        migrator.registerMigration("v2_rich_payload") { db in
            try db.alter(table: "repo_index") { t in
                t.add(column: "type", .text).notNull().defaults(to: RepoType.other.rawValue)
                t.add(column: "status", .text).notNull().defaults(to: GitStatus.clean.rawValue)
            }
        }
        return migrator
    }()

    public func load() async throws -> [IndexEntry] {
        try await dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT path, head_sha, type, status, last_scanned FROM repo_index ORDER BY path")
                .map { row in
                    // Unknown enum strings fall back to the neutral default rather than dropping
                    // the row — a forward-compat repo that this build doesn't recognize.
                    IndexEntry(path: row["path"],
                               headSHA: row["head_sha"],
                               type: RepoType(rawValue: row["type"]) ?? .other,
                               status: GitStatus(rawValue: row["status"]) ?? .clean,
                               lastScanned: Date(timeIntervalSince1970: row["last_scanned"]))
                }
        }
    }

    public func upsert(_ entries: [IndexEntry]) async throws {
        guard !entries.isEmpty else { return }
        try await dbQueue.write { db in
            for entry in entries {
                try db.execute(sql: """
                    INSERT INTO repo_index (path, head_sha, type, status, last_scanned)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(path) DO UPDATE SET
                        head_sha = excluded.head_sha,
                        type = excluded.type,
                        status = excluded.status,
                        last_scanned = excluded.last_scanned
                    """,
                    arguments: [entry.path, entry.headSHA, entry.type.rawValue, entry.status.rawValue,
                                entry.lastScanned.timeIntervalSince1970])
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
