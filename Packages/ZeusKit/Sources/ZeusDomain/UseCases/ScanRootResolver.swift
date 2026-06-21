import Foundation

/// Turns the user's *configured* scan roots (persisted path strings in `ZeusSettings.scanRoots`)
/// into the directory URLs the scanner should walk (P3-D, roots Slice 2A).
///
/// When the user hasn't configured anything, the supplied defaults (`ProjectScanner.defaultDevRoots`)
/// are used so the Hub is never empty by accident. When they have, their list is authoritative —
/// keeping only paths that still exist as directories so a deleted/renamed folder can't error the
/// walk (the same existence guard `defaultDevRoots` applies to the built-in roots).
public enum ScanRootResolver {
    public static func effectiveRoots(
        configured: [String],
        defaults: [URL],
        fileManager: FileManager = .default
    ) -> [URL] {
        guard !configured.isEmpty else { return defaults }
        return configured.compactMap { path in
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
                return nil
            }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
    }
}
