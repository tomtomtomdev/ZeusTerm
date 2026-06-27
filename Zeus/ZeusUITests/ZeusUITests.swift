//
//  ZeusUITests.swift
//  ZeusUITests
//
//  End-to-end UI coverage for the constellation flow. Runs against the deterministic
//  `-uiTestFixtures` build (sample data, placeholder terminal — see ZeusApp), driving the real
//  Hub → Worktree → Branch-tree path by accessibility identifier. This proves the slice-6
//  behavior — *selecting a commit shows that commit's diff* — through the actual UI, which unit
//  tests can't reach. The real-git data path stays unit-tested at the store/loader level.
//

import XCTest

final class ZeusUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uiTestFixtures"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// Hub → dive a repo → dive a worktree → the branch tree. Selecting a different commit must
    /// swap the Changes panel to that commit's diff (the changed-files list updates). The tappable
    /// constellation nodes carry the `.isButton` trait, so they surface to XCUITest as buttons.
    @MainActor
    func testSelectingACommitUpdatesTheChangesPanel() throws {
        // Hub: dive into a repo star.
        let star = app.buttons["hubStar.tuntun-api"]
        XCTAssertTrue(star.waitForExistence(timeout: 15), "Hub star should appear")
        star.tap()

        // Worktree orbit: dive into a worktree satellite.
        let worktree = app.buttons["worktree.hotfix/payment-retry"]
        XCTAssertTrue(worktree.waitForExistence(timeout: 10), "Worktree satellite should appear")
        worktree.tap()

        // Branch tree: HEAD/selected lands on the tip (12ab9c) → its diff shows by default.
        let tipFile = app.staticTexts["changes.file.Sources/Session/SessionStore.swift"]
        XCTAssertTrue(tipFile.waitForExistence(timeout: 10),
                      "Tip commit's changed files should populate the panel")

        // Select a different commit → the panel swaps to THAT commit's diff.
        let otherCommit = app.buttons["commit.aa55fe"]
        XCTAssertTrue(otherCommit.waitForExistence(timeout: 10), "Commit aa55fe should be on the tree")
        otherCommit.tap()

        let newFile = app.staticTexts["changes.file.Sources/Auth/OAuthFlow.swift"]
        XCTAssertTrue(newFile.waitForExistence(timeout: 10),
                      "Selecting aa55fe should show its changed files")
        XCTAssertFalse(tipFile.exists,
                       "The previously-selected commit's files should no longer be shown")
    }
}
