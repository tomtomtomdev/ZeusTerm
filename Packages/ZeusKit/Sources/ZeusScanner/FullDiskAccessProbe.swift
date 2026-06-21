import Foundation
import ZeusDomain

/// Reports Full Disk Access by attempting to read a TCC-gated path (P3-D, FDA hint). macOS exposes
/// no API that reports the grant directly, so the established convention is to read a file that is
/// only readable with Full Disk Access — the user's TCC database. If the read succeeds the app has
/// access; a TCC denial surfaces as a thrown error on open or read.
public struct FullDiskAccessProbe: FullDiskAccessChecking {
    private let probePath: String

    /// Defaults to the per-user TCC database, readable only with Full Disk Access. Injectable so the
    /// read→bool mapping is testable against an ordinary file.
    public init(probePath: String =
                NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db") {
        self.probePath = probePath
    }

    public func hasFullDiskAccess() -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: probePath)) else {
            return false
        }
        defer { try? handle.close() }
        // A successful read — even 0 bytes at EOF (read returns nil without throwing) — means access
        // was granted. Only a thrown error (how a TCC denial surfaces) means no access.
        do { _ = try handle.read(upToCount: 1); return true }
        catch { return false }
    }
}
