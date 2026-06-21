import Foundation
import ZeusDomain

/// Discovers git repositories by walking the filesystem, pruning heavy/irrelevant dirs.
/// P0 is a synchronous FileManager walk; Spotlight + FSEvents live updates land in P3 (SPEC §2.1).
public struct ProjectScanner: ProjectScanning {
    public var prunedDirectoryNames: Set<String>

    public static let defaultPruned: Set<String> = [
        "node_modules", ".build", "DerivedData", "Pods", "vendor", "target", ".venv",
    ]

    public init(prunedDirectoryNames: Set<String> = ProjectScanner.defaultPruned) {
        self.prunedDirectoryNames = prunedDirectoryNames
    }

    public func discoverRepositoryURLs(under roots: [URL]) async throws -> [URL] {
        // The walk is synchronous; NSEnumerator iteration is unavailable in async contexts.
        walk(roots)
    }

    public func rootEntryNames(at repo: URL) throws -> Set<String> {
        // Shallow listing only — classification keys off top-level marker files, and
        // descending would defeat the heavy-dir pruning the walk already paid for.
        Set(try FileManager.default.contentsOfDirectory(atPath: repo.path))
    }

    /// SPEC §2.1 default discovery roots under `home`, keeping only the ones that exist as
    /// directories (so the walk never errors on a missing folder). `home`/`fileManager` are
    /// injected for testability; the app calls it with the real home.
    public static func defaultDevRoots(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> [URL] {
        let names = ["Developer", "Projects", "Code", "src", "work", "git", "Documents", "Desktop"]
        return names.compactMap { name in
            let url = home.appendingPathComponent(name, isDirectory: true)
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
                return nil
            }
            return url
        }
    }

    private func walk(_ roots: [URL]) -> [URL] {
        let fm = FileManager.default
        var found: [URL] = []
        var seen = Set<URL>()
        func record(_ repo: URL) {
            if seen.insert(repo).inserted { found.append(repo) }
        }

        for root in roots {
            // A scan root that is ITSELF a repo owns its whole subtree — record it and don't walk
            // inside. Its build output, vendored deps, and submodules aren't separate top-level
            // projects. The in-loop `.git` branch below only prunes a discovered repo's subtree
            // when the repo surfaces as a child; the root never surfaces as its own child, so
            // without this its build/ (not in the pruned set) would still be descended into.
            if fm.fileExists(atPath: root.appendingPathComponent(".git").path) {
                record(root)
                continue
            }

            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let url as URL in enumerator {
                let name = url.lastPathComponent

                // A `.git` entry (dir, or a worktree/submodule pointer file) marks its PARENT as a
                // repo. Fallback net: a root-is-repo is pruned before this loop, and a child repo
                // is normally caught by the directory branch below (which skips its subtree before
                // `.git` is ever yielded). This still records the parent if a `.git` slips through.
                if name == ".git" {
                    record(url.deletingLastPathComponent())
                    enumerator.skipDescendants()
                    continue
                }

                // Skip heavy/build/dependency dirs by name before paying any stat cost.
                if prunedDirectoryNames.contains(name) {
                    enumerator.skipDescendants()
                    continue
                }

                // A subdirectory that contains `.git` is a repo root: record it and prune its
                // ENTIRE subtree. A repo's vendored deps, submodules, and build artifacts are not
                // separate top-level projects — and `skipDescendants()` on the `.git` entry alone
                // wouldn't stop the walk from descending into sibling dirs like `build/` (which
                // isn't in the pruned set), where a SwiftPM checkout's nested `.git` would
                // otherwise be mis-indexed as its own project.
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDirectory, fm.fileExists(atPath: url.appendingPathComponent(".git").path) {
                    record(url)
                    enumerator.skipDescendants()
                }
            }
        }
        return found
    }
}
