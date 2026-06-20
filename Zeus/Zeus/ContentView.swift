//
//  ContentView.swift
//  Zeus
//
//  Created by tomtomtom on 6/19/26.
//
//  The app's root: the ZeusTerm constellation (SPEC §7), driven by ZeusUI's ConstellationShell
//  with a live PTY (ZeusTerminal) in the bottom panel. This is the composition root (CLAUDE.md):
//  it wires the concrete adapters (ProjectScanner + GitCLIService + a GRDB scan index) into
//  HubDataStore so the Hub paints instantly from the persisted index, then reconciles with a live
//  scan of the SPEC §2.1 dev roots. The app is non-sandboxed (SPEC §8) so the scan + embedded
//  login shell can reach the filesystem (Full Disk Access on first run).

import SwiftUI
import Foundation
import ZeusUI
import ZeusTerminal
import ZeusDomain
import ZeusScanner
import ZeusGit
import ZeusIndex

struct ContentView: View {
    @State private var hubData = HubDataStore(
        loader: HubDataLoader(scanner: ProjectScanner(),
                              git: GitCLIService(),
                              index: ContentView.makeIndexStore()),
        roots: ProjectScanner.defaultDevRoots())

    /// Opens the persisted scan index at `~/Library/Application Support/Zeus/index.sqlite`,
    /// creating the directory if needed. Returns nil on any failure (e.g. an unwritable container)
    /// so the loader cleanly falls back to a full live scan rather than blocking startup.
    private static func makeIndexStore() -> GRDBRepositoryIndexStore? {
        let fileManager = FileManager.default
        guard let appSupport = try? fileManager.url(for: .applicationSupportDirectory,
                                                    in: .userDomainMask,
                                                    appropriateFor: nil,
                                                    create: true) else { return nil }
        let directory = appSupport.appendingPathComponent("Zeus", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let dbPath = directory.appendingPathComponent("index.sqlite").path
        return try? GRDBRepositoryIndexStore(path: dbPath)
    }

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
