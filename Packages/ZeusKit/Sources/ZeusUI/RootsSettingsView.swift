import SwiftUI
import AppKit

/// Settings pane for the user's scan roots (feature #1, P3-D, Slice 2C). Thin glue over the
/// `SettingsStore`: the list rendering + add/remove/reset wiring live here, while the editing
/// logic and persistence sit in the store (unit-tested). The NSOpenPanel folder picker is an
/// AppKit modal that can't be unit-tested, so this view is proven with /verify. Styled natively
/// (a grouped `Form`) rather than with the constellation `Theme` so it reads as a Mac settings pane.
public struct RootsSettingsView: View {
    @State private var store: SettingsStore

    public init(store: SettingsStore) {
        _store = State(initialValue: store)
    }

    public var body: some View {
        Form {
            Section {
                if store.scanRoots.isEmpty {
                    Label("Scanning the built-in developer folders (Developer, Projects, Code, Desktop, …).",
                          systemImage: "sparkles")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.scanRoots, id: \.self) { path in
                        HStack {
                            Image(systemName: "folder").foregroundStyle(.secondary)
                            Text(abbreviate(path))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(path)
                            Spacer()
                            Button {
                                store.removeRoot(path)
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                            .help("Stop scanning this folder")
                        }
                    }
                }
            } header: {
                Text("Folders Zeus scans for git projects")
            } footer: {
                Text("Add the folders that hold your repositories. With none added, Zeus scans the built-in developer folders.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Add Folder…", systemImage: "plus") { addFolder() }
                    Spacer()
                    Button("Reset to Defaults") { store.resetRoots() }
                        .disabled(store.scanRoots.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 320)
    }

    /// Native folder picker — directories only, single selection.
    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.message = "Choose a folder to scan for git projects"
        if panel.runModal() == .OK, let url = panel.url {
            store.addRoot(url.path)
        }
    }

    /// Show `~/Desktop` rather than the full `/Users/…/Desktop`.
    private func abbreviate(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
