import SwiftUI
import ZeusDomain

/// The top-level three-pane shell: project rail | repo tree | terminal pane
/// (features #5 side-tabs, #2 tree, #6 terminal, #7 gradient). P0 shows placeholder
/// content; later phases bind each pane to its store.
public struct AppShellView: View {
    public var gradient: GradientConfig

    public init(gradient: GradientConfig = .aurora) {
        self.gradient = gradient
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
                VStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.system(size: 40))
                    Text("Terminal")
                        .font(.title2.weight(.semibold))
                }
                .foregroundStyle(.white)
            }
            .navigationTitle("Terminal")
        }
    }
}

#Preview {
    AppShellView()
        .frame(width: 900, height: 600)
}
