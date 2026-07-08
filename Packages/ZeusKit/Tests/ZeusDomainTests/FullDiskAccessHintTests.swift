import Foundation
import Testing
@testable import ZeusDomain

/// P3-D (FDA hint) — the pure rule that decides whether to nudge the user toward Full Disk Access.
///
/// Why this exists: FSEvents live-refresh silently never fires on TCC-protected user folders
/// (Desktop/Documents/Downloads) without Full Disk Access, even though the per-folder access the
/// *scan* uses is granted. The hint should only show when it actually matters — access is absent
/// AND at least one watched root lives in a protected folder. A user who only watches `~/code`
/// gets live refresh without FDA and must not be nagged.
///
/// Pure: takes the access state, the watched roots, and the home directory — no I/O, no probing.
///
/// Test List:
///  [x] has access                          → never needed (regardless of roots)
///  [x] no access + a root under ~/Documents → needed
///  [x] no access + only non-protected roots → not needed
///  [x] no access + root IS ~/Desktop itself → needed (exact match, not just descendants)
///  [x] no access + ~/Documentsomething      → not needed (sibling-prefix guard, cf. D.3d)
struct FullDiskAccessHintTests {

    private let home = URL(fileURLWithPath: "/Users/zeus")

    @Test func grantedAccessNeverNeedsTheHint() {
        let needed = FullDiskAccessHint.isNeeded(
            hasAccess: true,
            roots: [home.appendingPathComponent("Documents")],
            home: home)

        #expect(needed == false)
    }

    @Test func missingAccessUnderAProtectedFolderNeedsTheHint() {
        let needed = FullDiskAccessHint.isNeeded(
            hasAccess: false,
            roots: [home.appendingPathComponent("Documents/ttsecuritas")],
            home: home)

        #expect(needed == true)
    }

    @Test func missingAccessWithOnlyNonProtectedRootsDoesNotNeedTheHint() {
        let needed = FullDiskAccessHint.isNeeded(
            hasAccess: false,
            roots: [home.appendingPathComponent("code"), home.appendingPathComponent("Developer")],
            home: home)

        #expect(needed == false)
    }

    @Test func aProtectedFolderItselfNeedsTheHint() {
        let needed = FullDiskAccessHint.isNeeded(
            hasAccess: false,
            roots: [home.appendingPathComponent("Desktop")],
            home: home)

        #expect(needed == true)
    }

    @Test func aSiblingPrefixOfAProtectedFolderDoesNotNeedTheHint() {
        // `~/Documentsbackup` is NOT under `~/Documents` — a bare hasPrefix would wrongly match.
        let needed = FullDiskAccessHint.isNeeded(
            hasAccess: false,
            roots: [home.appendingPathComponent("Documentsbackup")],
            home: home)

        #expect(needed == false)
    }

    // A protected folder exists on disk but was left OUT of the scan roots because we lack access
    // (defaults exclude Desktop/Documents/Downloads without FDA). The user would never learn they
    // could see those repos — so nudge them, even though no watched root is protected.
    @Test func aPresentButExcludedProtectedFolderNeedsTheHint() {
        let needed = FullDiskAccessHint.isNeeded(
            hasAccess: false,
            roots: [home.appendingPathComponent("Developer")],
            home: home,
            excludedProtectedFolders: ["Documents"])

        #expect(needed == true)
    }

    @Test func aPresentButExcludedProtectedFolderWithAccessDoesNotNeedTheHint() {
        // With access, the widened defaults already include the folder — nothing to nudge for.
        let needed = FullDiskAccessHint.isNeeded(
            hasAccess: true,
            roots: [home.appendingPathComponent("Developer")],
            home: home,
            excludedProtectedFolders: ["Documents"])

        #expect(needed == false)
    }

    @Test func noExcludedFoldersAndOnlyNonProtectedRootsDoesNotNeedTheHint() {
        // The new parameter defaults to empty and must not change the original behavior.
        let needed = FullDiskAccessHint.isNeeded(
            hasAccess: false,
            roots: [home.appendingPathComponent("code")],
            home: home,
            excludedProtectedFolders: [])

        #expect(needed == false)
    }
}
