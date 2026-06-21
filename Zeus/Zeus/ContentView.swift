//
//  ContentView.swift
//  Zeus
//
//  Created by tomtomtom on 6/19/26.
//
//  The app's root view: the ZeusTerm constellation (SPEC §7), driven by ZeusUI's ConstellationShell
//  with a live PTY (ZeusTerminal) in the bottom panel. The stores are built by AppComposition and
//  injected from ZeusApp (so the Settings scene shares the same SettingsStore). When the user edits
//  their scan roots, the Hub re-scans without a relaunch.
//

import SwiftUI
import Foundation
import ZeusUI
import ZeusTerminal

struct ContentView: View {
    let hubData: HubDataStore
    let settings: SettingsStore

    var body: some View {
        ConstellationShell(theme: .dark, hubData: hubData) {
            TerminalEmulatorView(workingDirectory: FileManager.default.homeDirectoryForCurrentUser)
        }
        .frame(minWidth: 1100, minHeight: 720)
        .onChange(of: settings.scanRoots) { _, _ in
            let roots = AppComposition.effectiveRoots(for: settings)
            Task { await hubData.reload(roots: roots) }
        }
    }
}

#Preview {
    // Placeholder terminal keeps the preview lightweight (no live PTY, no real scan).
    ConstellationShell(theme: .dark)
        .frame(width: 1040, height: 720)
}
