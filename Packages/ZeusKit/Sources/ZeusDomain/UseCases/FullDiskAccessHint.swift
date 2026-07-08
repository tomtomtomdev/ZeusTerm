import Foundation

/// The pure rule deciding whether to nudge the user toward Full Disk Access (P3-D, FDA hint).
///
/// FSEvents live-refresh silently never fires on TCC-protected user folders without Full Disk
/// Access — even though the per-folder access the *scan* relies on is granted independently. So the
/// Hub keeps painting from the last scan but never updates live. This rule keeps the nudge honest:
/// show it only when access is absent AND at least one watched root is in a protected folder. Roots
/// elsewhere (e.g. `~/code`) get live refresh without FDA and must not trigger the hint.
///
/// Pure: no probing here — the caller supplies `hasAccess` (the adapter probes) and `home`.
public enum FullDiskAccessHint {

    /// The user folders macOS gates behind Full Disk Access for filesystem observation. These are
    /// the default scan roots most likely to hold repos (cf. `ProjectScanner.defaultDevRoots`).
    public static let protectedFolderNames: Set<String> = ["Desktop", "Documents", "Downloads"]

    /// Whether to nudge the user toward Full Disk Access. Only when access is absent AND either:
    ///  - a watched root lives in (or under) a protected folder (FSEvents live-refresh silently
    ///    never fires there without FDA), or
    ///  - `excludedProtectedFolders` is non-empty — a protected folder exists on disk but was left
    ///    out of the scan roots because we lack access (the defaults exclude them without FDA, so
    ///    the user would otherwise never learn those repos could be shown).
    public static func isNeeded(
        hasAccess: Bool,
        roots: [URL],
        home: URL,
        excludedProtectedFolders: Set<String> = []
    ) -> Bool {
        guard !hasAccess else { return false }
        if !excludedProtectedFolders.isEmpty { return true }
        let protectedRoots = protectedFolderNames.map { home.appendingPathComponent($0) }
        return roots.contains { root in
            protectedRoots.contains { isPath(root, atOrUnder: $0) }
        }
    }

    /// `path` is the directory `ancestor` itself or a descendant of it. The trailing separator on
    /// the prefix check stops `~/Documentsbackup` from matching `~/Documents` (same sibling-prefix
    /// guard as the incremental rescan planner, P3-D.3d).
    public static func isPath(_ path: URL, atOrUnder ancestor: URL) -> Bool {
        path.path == ancestor.path || path.path.hasPrefix(ancestor.path + "/")
    }

    /// Whether `path` is at or under any TCC-protected user folder in `home` — used by the roots UI
    /// to spot when a user picks a folder whose scan/live-refresh will need Full Disk Access.
    public static func isProtected(_ path: URL, home: URL) -> Bool {
        protectedFolderNames.contains { isPath(path, atOrUnder: home.appendingPathComponent($0)) }
    }
}
