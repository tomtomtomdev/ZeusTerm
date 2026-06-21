import Testing
import Foundation
@testable import ZeusScanner

/// P3-D (FDA hint, adapter) — `FullDiskAccessProbe` reports Full Disk Access by attempting to read
/// a TCC-gated path. No Apple API reports the grant directly; the convention is to read a file only
/// readable with FDA (the user's `~/Library/Application Support/com.apple.TCC/TCC.db`). The probe
/// path is injected so the read→bool mapping is testable without depending on the host's real grant.
///
/// Test List:
///  [x] a readable file              → hasFullDiskAccess() == true  (open + read succeed)
///  [x] a nonexistent (unopenable) path → hasFullDiskAccess() == false (open throws)
struct FullDiskAccessProbeTests {

    @Test func reportsAccessWhenTheProbePathIsReadable() throws {
        let fm = FileManager.default
        let file = fm.temporaryDirectory.appendingPathComponent("zeus-fda-\(UUID().uuidString)")
        try "probe".write(to: file, atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(at: file) }

        let probe = FullDiskAccessProbe(probePath: file.path)

        #expect(probe.hasFullDiskAccess() == true)
    }

    @Test func reportsNoAccessWhenTheProbePathCannotBeOpened() {
        let ghost = FileManager.default.temporaryDirectory
            .appendingPathComponent("zeus-fda-gone-\(UUID().uuidString)").path

        let probe = FullDiskAccessProbe(probePath: ghost)

        #expect(probe.hasFullDiskAccess() == false)
    }
}
