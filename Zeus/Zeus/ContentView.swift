//
//  ContentView.swift
//  Zeus
//
//  Created by tomtomtom on 6/19/26.
//
//  The app's root: the ZeusTerm constellation (SPEC §7), driven by ZeusUI's ConstellationShell
//  with a live PTY (ZeusTerminal) in the bottom panel. This is the composition root (CLAUDE.md):
//  it wires the concrete adapters (ProjectScanner + GitCLIService) into HubDataStore so the Hub
//  renders a live scan of the SPEC §2.1 dev roots. The app is non-sandboxed (SPEC §8) so the
//  scan + embedded login shell can reach the filesystem (Full Disk Access on first run).

import SwiftUI
import ZeusUI
import ZeusTerminal
import ZeusDomain
import ZeusScanner
import ZeusGit

struct ContentView: View {
    @State private var hubData = HubDataStore(
        loader: HubDataLoader(scanner: ProjectScanner(), git: GitCLIService()),
        roots: ProjectScanner.defaultDevRoots())

    var body: some View {
        ConstellationShell(theme: .dark, hubData: hubData) {
            TerminalEmulatorView(workingDirectory: FileManager.default.homeDirectoryForCurrentUser)
        }
        .frame(minWidth: 1100, minHeight: 720)
    }
}

#Preview {
    // Placeholder terminal keeps the preview lightweight (no live PTY).
    ConstellationShell(theme: .dark)
        .frame(width: 1040, height: 720)
}
