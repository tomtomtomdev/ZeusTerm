import Foundation

/// Pure policy (P3-D.3a) deciding whether a filesystem change reported by the
/// `FileSystemWatching` port warrants a Hub rescan. FSEvents fires for *every* change under the
/// watched roots; a rescan walks the tree and shells out to `git`, so changes that run through a
/// heavy/build/dependency dir (a `node_modules` install, Xcode writing `DerivedData`, etc.) are
/// dropped before they can trigger one. The store applies this filter ahead of its debounce.
public struct ChangeRelevance: Sendable {
    /// Heavy/build/dependency directory names whose internal churn never changes the Hub.
    /// Mirrors `ProjectScanner.defaultPruned` (the adapter's walk prunes the same dirs); the
    /// composition root can inject one shared set so the two can't drift.
    public let prunedDirectoryNames: Set<String>

    public static let defaultPruned: Set<String> = [
        "node_modules", ".build", "DerivedData", "Pods", "vendor", "target", ".venv",
    ]

    public init(prunedDirectoryNames: Set<String> = ChangeRelevance.defaultPruned) {
        self.prunedDirectoryNames = prunedDirectoryNames
    }

    /// True when a change at `changedPath` could affect the Hub (the repo set, a repo's type,
    /// or its git status). Irrelevant when any path component is a pruned dir name — the change
    /// happened inside dependency/build output we never index.
    public func isRelevant(changedPath: String) -> Bool {
        let components = Set(changedPath.split(separator: "/").map(String.init))
        return components.isDisjoint(with: prunedDirectoryNames)
    }
}
