import Foundation

/// File change status for the branch-tree Changes panel (SPEC §6/§7, View 3).
public enum FileStatus: String, Sendable, Hashable { case added, modified, deleted }

/// One changed file in a commit: path, status, and line counts.
public struct FileChange: Identifiable, Sendable, Hashable {
    public var id: String { path }
    public var path: String
    public var status: FileStatus
    public var additions: Int
    public var deletions: Int

    public init(path: String, status: FileStatus, additions: Int, deletions: Int) {
        self.path = path; self.status = status
        self.additions = additions; self.deletions = deletions
    }
}

/// A commit's changed files plus the unified diff text for the preview pane.
public struct CommitDiff: Sendable, Hashable {
    public var sha: String
    public var files: [FileChange]
    public var patch: String

    public init(sha: String, files: [FileChange], patch: String) {
        self.sha = sha; self.files = files; self.patch = patch
    }
}
