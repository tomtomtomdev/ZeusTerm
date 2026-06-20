//
//  ContentView.swift
//  Zeus
//
//  Created by tomtomtom on 6/19/26.
//
//  The app's root: the ZeusTerm constellation (SPEC §7), driven by ZeusUI's ConstellationShell
//  over the sample data, with a live PTY (ZeusTerminal) embedded in the bottom panel. The app is
//  non-sandboxed (SPEC §8) so the embedded login shell can reach the filesystem.

import SwiftUI
import ZeusUI
import ZeusTerminal

struct ContentView: View {
    var body: some View {
        ConstellationShell(theme: .dark) {
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
