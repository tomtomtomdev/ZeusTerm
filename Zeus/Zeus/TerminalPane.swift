//
//  TerminalPane.swift
//  Zeus
//
//  The bottom-panel terminal unit for a single working directory (P6, feature #4): a live PTY with
//  the app-managed suggestion line (SPEC §2.4) docked beneath it. Both are driven by ONE
//  `TerminalController`, so a command accepted with `→` and committed with `Enter` in the line is
//  injected into the exact shell shown above — the reconciliation that closes P6 (there is no
//  separate session adapter anymore; the controller *is* the `TerminalSessionControlling` port).
//
//  ConstellationShell gives this view a per-cwd identity (`.id(cwd)`), so diving in/out rebuilds the
//  pane and thus a fresh controller rooted in the new directory. The controller is held in `@State`
//  so it survives ordinary re-renders (e.g. a theme change) and is created once per cwd.
//

import SwiftUI
import Foundation
import ZeusUI
import ZeusTerminal

struct TerminalPane: View {
    private let suggestion: SuggestionStore
    private let theme: Theme
    @State private var controller: TerminalController

    init(cwd: URL, suggestion: SuggestionStore, theme: Theme) {
        self.suggestion = suggestion
        self.theme = theme
        _controller = State(initialValue: TerminalController(workingDirectory: cwd))
    }

    var body: some View {
        VStack(spacing: 0) {
            TerminalEmulatorView(controller: controller)
            SuggestionInputLine(store: suggestion, session: controller, theme: theme)
        }
    }
}
