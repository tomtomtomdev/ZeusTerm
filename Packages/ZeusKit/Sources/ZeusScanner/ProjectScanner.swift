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
        let names = ["Developer", "Projects", "Code", "src", "work", "git", "Documents"]
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

        for root in roots {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let url as URL in enumerator {
                let name = url.lastPathComponent
                if name == ".git" {
                    let repo = url.deletingLastPathComponent()
                    if seen.insert(repo).inserted { found.append(repo) }
                    enumerator.skipDescendants()
                } else if prunedDirectoryNames.contains(name) {
                    enumerator.skipDescendants()
                }
            }
        }
        return found
    }
}
