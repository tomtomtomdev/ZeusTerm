import SwiftUI
import ZeusDomain

/// The top-level three-pane shell: project rail | repo tree | terminal pane
/// (features #5 side-tabs, #2 tree, #6 terminal, #7 gradient). P0 shows placeholder
/// content; later phases bind each pane to its store.
///
/// The terminal pane content is injected via a `@ViewBuilder` so this UI layer stays
/// decoupled from `ZeusTerminal` (and its SwiftTerm dependency) — the composition root
/// supplies the live `TerminalEmulatorView`; the no-arg initializer shows a placeholder.
public struct AppShellView<TerminalContent: View>: View {
    public var gradient: GradientConfig
    private let terminalContent: TerminalContent

    public init(
        gradient: GradientConfig = .aurora,
        @ViewBuilder terminalContent: () -> TerminalContent
    ) {
        self.gradient = gradient
        self.terminalContent = terminalContent()
    }

    public var body: some View {
        NavigationSplitView {
            List {
                Label("Zeus", systemImage: "bolt.fill")
            }
            .navigationTitle("Projects")
            .frame(minWidth: 200)
        } content: {
            List {
                Text("Repo → Worktree → Branch → Commits")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Tree")
            .frame(minWidth: 280)
        } detail: {
            ZStack {
                GradientBackground(config: gradient)
                terminalContent
            }
            .navigationTitle("Terminal")
        }
    }
}

/// Placeholder shown when no live terminal is injected (P0 / previews).
public struct TerminalPlaceholder: View {
    public init() {}
    public var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 40))
            Text("Terminal")
                .font(.title2.weight(.semibold))
        }
        .foregroundStyle(.white)
    }
}

extension AppShellView where TerminalContent == TerminalPlaceholder {
    public init(gradient: GradientConfig = .aurora) {
        self.init(gradient: gradient) { TerminalPlaceholder() }
    }
}

#Preview {
    AppShellView()
        .frame(width: 900, height: 600)
}
