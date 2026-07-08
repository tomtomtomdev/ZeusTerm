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
    let orbitData: WorktreeOrbitStore
    let treeData: CommitTreeStore
    let diffData: CommitDiffStore
    let settings: SettingsStore
    // P6 (feature #4): the app-managed suggestion line's state, shared across the whole session so
    // frecency/history persist as the user dives between repos. It's docked under the PTY by
    // TerminalPane, which pairs it with a per-cwd TerminalController so a committed command reaches
    // the shell the user is looking at.
    let suggestion: SuggestionStore

    var body: some View {
        ConstellationShell(theme: Theme(mode: settings.theme), settings: settings,
                           hubData: hubData, orbitData: orbitData,
                           treeData: treeData, diffData: diffData) { cwd in
            // The shell hands us the dived-into repo path (home at the hub) with a per-cwd `.id`, so
            // each dive builds a fresh pane: a PTY opened there plus the suggestion line over it.
            TerminalPane(cwd: cwd, suggestion: suggestion, theme: Theme(mode: settings.theme))
        }
        .frame(minWidth: 1100, minHeight: 720)
        .onChange(of: settings.scanRoots) { _, _ in
            let roots = AppComposition.effectiveRoots(for: settings)
            Task { await hubData.reload(roots: roots) }
        }
    }
}

#Preview {
    // Sample-backed, placeholder terminal — keeps the preview lightweight (no live PTY, no scan).
    ConstellationShell.sample(theme: .dark)
        .frame(width: 1040, height: 720)
}
