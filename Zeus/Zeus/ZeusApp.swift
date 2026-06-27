//
//  ZeusApp.swift
//  Zeus
//
//  Created by tomtomtom on 6/19/26.
//
//  Composition root: builds the shared SettingsStore + HubDataStore once and injects them into
//  both the main constellation window and the Settings scene (so edits in Settings drive the
//  same store the Hub observes).
//

import SwiftUI
import ZeusUI

@main
struct ZeusApp: App {
    /// UI-test hook: when launched with `-uiTestFixtures`, render the deterministic, sample-backed
    /// constellation (no real scan / git / Full Disk Access, placeholder terminal) so XCUITests can
    /// drive the Hub → Worktree → Branch-tree flow reliably by accessibility identifier (see
    /// ZeusUITests). The real-git path stays unit-tested at the store/loader level; this only
    /// stabilizes the *UI* flow against host-dependent data.
    private let uiTestFixtures = ProcessInfo.processInfo.arguments.contains("-uiTestFixtures")

    @State private var settings: SettingsStore
    @State private var hubData: HubDataStore
    @State private var orbitData: WorktreeOrbitStore
    @State private var treeData: CommitTreeStore
    @State private var diffData: CommitDiffStore

    init() {
        let settingsStore = SettingsStore(store: AppComposition.makeSettingsStore())
        _settings = State(initialValue: settingsStore)
        _hubData = State(initialValue: AppComposition.makeHubStore(settings: settingsStore))
        _orbitData = State(initialValue: AppComposition.makeOrbitStore())
        _treeData = State(initialValue: AppComposition.makeTreeStore())
        _diffData = State(initialValue: AppComposition.makeDiffStore())
    }

    var body: some Scene {
        WindowGroup {
            if uiTestFixtures {
                ConstellationShell.sample(theme: .dark)
                    .frame(minWidth: 1100, minHeight: 720)
            } else {
                ContentView(hubData: hubData, orbitData: orbitData, treeData: treeData,
                            diffData: diffData, settings: settings)
            }
        }
        .defaultSize(width: 1320, height: 860)

        Settings {
            RootsSettingsView(store: settings)
        }
    }
}
