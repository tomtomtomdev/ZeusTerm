import SwiftUI
import AppKit
import ZeusDomain

/// Settings pane for appearance (feature #7, P7-F): theme, the configurable gradient background with
/// a **live preview**, the preset catalog, per-field controls, and JSON import/export. Thin glue over
/// `SettingsStore` — every mutation is an already-unit-tested store intent; the NSOpen/SavePanel
/// modals and the live SwiftUI preview can't be unit-tested, so this view is proven with /verify.
public struct AppearanceSettingsView: View {
    @State private var store: SettingsStore
    @State private var importError: String?

    public init(store: SettingsStore) {
        _store = State(initialValue: store)
    }

    public var body: some View {
        Form {
            Section("Live preview") {
                GradientBackground(config: store.gradient)
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
                    .listRowInsets(EdgeInsets())
            }

            Section("Presets") {
                HStack {
                    ForEach(GradientConfig.presets, id: \.name) { preset in
                        Button(preset.name) { store.applyGradientPreset(named: preset.name) }
                            .buttonStyle(.bordered)
                    }
                }
            }

            Section("Theme") {
                Picker("Appearance", selection: themeBinding) {
                    Text("Dark").tag(ThemeMode.dark)
                    Text("Light").tag(ThemeMode.light)
                }
                .pickerStyle(.segmented)
            }

            Section("Gradient") {
                Picker("Style", selection: field(\.style)) {
                    ForEach(GradientConfig.Style.allCases, id: \.self) { style in
                        Text(style.rawValue.capitalized).tag(style)
                    }
                }
                Toggle("Animated", isOn: field(\.animated))
                LabeledContent("Speed") {
                    Slider(value: field(\.animationSpeed), in: 0.25...3)
                }
                .disabled(!store.gradient.animated)
                LabeledContent("Opacity") {
                    Slider(value: field(\.backgroundOpacity), in: 0...1)
                }
            }

            Section {
                HStack {
                    Button("Import JSON…", systemImage: "square.and.arrow.down") { importJSON() }
                    Spacer()
                    Button("Export JSON…", systemImage: "square.and.arrow.up") { exportJSON() }
                }
            } footer: {
                Text("Share or back up a gradient as a JSON file (SPEC §2.7).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 520)
        .alert("Couldn’t import gradient",
               isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    // MARK: - Bindings

    /// A binding into one gradient field that routes writes through the store's `updateGradient`
    /// intent (which persists), so the view stays a Humble Object.
    private func field<T>(_ keyPath: WritableKeyPath<GradientConfig, T>) -> Binding<T> {
        Binding(
            get: { store.gradient[keyPath: keyPath] },
            set: { newValue in
                var next = store.gradient
                next[keyPath: keyPath] = newValue
                store.updateGradient(next)
            }
        )
    }

    private var themeBinding: Binding<ThemeMode> {
        Binding(get: { store.theme }, set: { store.setTheme($0) })
    }

    // MARK: - Import / export (AppKit modals)

    private func importJSON() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.prompt = "Import"
        panel.message = "Choose a gradient JSON file"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.importGradient(fromJSON: String(contentsOf: url, encoding: .utf8))
        } catch {
            importError = error.localizedDescription
        }
    }

    private func exportJSON() {
        guard let json = try? store.exportedGradientJSON() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "zeus-gradient.json"
        panel.prompt = "Export"
        if panel.runModal() == .OK, let url = panel.url {
            try? json.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
