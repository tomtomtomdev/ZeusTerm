import SwiftUI
import AppKit
import ZeusDomain

/// The constellation window (SPEC §7): a 54px topbar, a body of { 236px rail | zoom canvas }, and
/// a bottom panel that is the PTY terminal on hub/worktree levels or the Changes panel on the
/// branch tree. Owns the `NavigationStore` (UDF) and the active `Theme`; the terminal pane is
/// injected via a `@ViewBuilder` so this layer stays decoupled from `ZeusTerminal` (SwiftTerm).
public struct ConstellationShell<TerminalContent: View>: View {
    @State private var store: NavigationStore
    @State private var theme: Theme
    /// nil in previews / the ZoomSpike harness (Hub falls back to `SampleConstellationData`);
    /// the app injects a real one so the Hub renders the live scan.
    @State private var hubData: HubDataStore?
    /// nil in previews (the worktree level falls back to `SampleConstellationData`); the app injects
    /// a real one so diving into a repo shows that repo's real worktrees loaded from git.
    @State private var orbitData: WorktreeOrbitStore?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let terminalContent: TerminalContent

    public init(theme: Theme = .dark,
                store: NavigationStore = NavigationStore(),
                hubData: HubDataStore? = nil,
                orbitData: WorktreeOrbitStore? = nil,
                @ViewBuilder terminalContent: () -> TerminalContent) {
        _store = State(initialValue: store)
        _theme = State(initialValue: theme)
        _hubData = State(initialValue: hubData)
        _orbitData = State(initialValue: orbitData)
        self.terminalContent = terminalContent()
    }

    private var presenter: ConstellationPresenter { ConstellationPresenter(state: store.state) }

    public var body: some View {
        VStack(spacing: 0) {
            ConstellationTopBar(presenter: presenter, theme: theme,
                                onCrumb: { store.dispatch(.backTo($0)) },
                                onToggleTheme: { theme = theme.toggled })
            Divider().overlay(theme.accentSoft)
            if hubData?.liveRefreshNeedsFullDiskAccess == true {
                FullDiskAccessBanner(theme: theme) { hubData?.dismissFullDiskAccessHint() }
                Divider().overlay(theme.accentSoft)
            }
            HStack(spacing: 0) {
                ConstellationRail(theme: theme)
                Divider().overlay(theme.accentSoft)
                canvas
            }
            Divider().overlay(theme.accentSoft)
            bottomPanel
        }
        .background(theme.appBackground)
        .task { store.setReduceMotion(reduceMotion) }
        .task { await hubData?.load() }
        .onChange(of: reduceMotion) { _, now in store.setReduceMotion(now) }
        // Diving into a repo sets `projectPath` (at phaseAdvance); load that repo's real worktrees
        // so the orbit level reflects the dived-into repo rather than the sample fixture.
        .onChange(of: store.state.projectPath) { _, path in
            guard let path else { return }
            orbitData?.load(repoPath: URL(fileURLWithPath: path))
        }
    }

    /// Hub source: the live scan once loaded, an empty hub while scanning, and the sample
    /// fixture when no real store is injected (previews / ZoomSpike).
    private var displayHub: ConstellationHub {
        if let hubData { return hubData.hub ?? HubFallback.loading }
        return SampleConstellationData.hub
    }

    /// True while a real store is injected and its first scan hasn't completed.
    private var isScanning: Bool { hubData != nil && hubData?.hub == nil }

    /// Worktree source: the dived-into repo's real orbits once loaded, an empty orbit (just the
    /// repo star) while loading, and the sample fixture when no real store is injected (previews).
    private var displayOrbits: ConstellationOrbits {
        if let orbitData {
            return orbitData.orbits ?? .empty(center: WorktreeOrbitStore.defaultCenter)
        }
        return SampleConstellationData.orbits
    }

    // MARK: Canvas (zoom stage + floating Back pill)

    private var canvas: some View {
        ZStack(alignment: .topLeading) {
            RadialGradient(colors: [theme.elevated.opacity(0.5), theme.appBackground],
                           center: .center, startRadius: 0, endRadius: 520)
                .ignoresSafeArea()

            ConstellationStage(presenter: presenter) { stageContent }
                .allowsHitTesting(presenter.pointerEnabled)

            if presenter.showsBackPill {
                BackPill(theme: theme) { store.dispatch(.back) }
                    .padding(14)
            }

            if isScanning {
                ScanningIndicator(theme: theme)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    @ViewBuilder private var stageContent: some View {
        switch store.state.view {
        case .hub:
            HubLevelView(hub: displayHub, theme: theme) { star in
                // `star.id` is the repo's filesystem path (real scans) — carried so the worktree
                // level can load that repo's real git data; `star.name` stays the display label.
                store.dispatch(.dive(to: .work, focal: star.point,
                                     context: DiveContext(project: star.name, projectPath: star.id)))
            }
        case .work:
            OrbitLevelView(orbits: displayOrbits, theme: theme) { sat in
                store.dispatch(.dive(to: .tree, focal: sat.point,
                                     context: DiveContext(worktreeBranch: sat.branch,
                                                          tip: SampleConstellationData.tipSHA)))
            }
        case .tree:
            TreeLevelView(tree: SampleConstellationData.tree,
                          head: store.state.head,
                          selected: store.state.selected,
                          theme: theme,
                          onSelect: { store.dispatch(.selectCommit($0)) },
                          onCheckout: { store.dispatch(.checkout($0)) })
        }
    }

    // MARK: Bottom panel (terminal vs Changes)

    @ViewBuilder private var bottomPanel: some View {
        switch presenter.bottomPanel {
        case .terminal:
            ZStack { theme.panel; terminalContent }
                .frame(height: 196)
        case .changes:
            let selected = SampleConstellationData.tree.nodes.first { $0.id == store.state.selected }
            ChangesPanelView(commit: selected,
                             diff: SampleConstellationData.diff(forSHA: store.state.selected),
                             isHead: presenter.selectedIsHead,
                             theme: theme,
                             onCheckout: { store.dispatch(.checkout($0)) })
                .frame(height: 232)
        }
    }
}

// Convenience: a shell with the placeholder terminal (previews / before the live PTY is wired in).
extension ConstellationShell where TerminalContent == TerminalPlaceholder {
    public init(theme: Theme = .dark, store: NavigationStore = NavigationStore()) {
        self.init(theme: theme, store: store) { TerminalPlaceholder() }
    }
}

// MARK: - Topbar

struct ConstellationTopBar: View {
    let presenter: ConstellationPresenter
    let theme: Theme
    let onCrumb: (Level) -> Void
    let onToggleTheme: () -> Void

    private static let levels: [Level] = [.hub, .work, .tree]

    var body: some View {
        HStack(spacing: 12) {
            Label("ZeusTerm", systemImage: "bolt.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.gold)

            Rectangle().fill(theme.accentSoft).frame(width: 1, height: 18)

            breadcrumb

            if let detached = presenter.detachedLabel {
                Text(detached)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(theme.statusColor(.behind).opacity(0.18), in: Capsule())
                    .foregroundStyle(theme.statusColor(.behind))
            }

            Spacer()

            Button(action: onToggleTheme) {
                Image(systemName: theme == .dark ? "sun.max" : "moon.fill")
                    .foregroundStyle(theme.textMid)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(theme == .dark ? "Switch to light theme" : "Switch to dark theme")
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(theme.rail)
    }

    private var breadcrumb: some View {
        let crumbs = presenter.breadcrumb
        return HStack(spacing: 6) {
            ForEach(Array(crumbs.enumerated()), id: \.offset) { index, crumb in
                if index > 0 {
                    Text("/").foregroundStyle(theme.textDim).font(.system(size: 12))
                }
                let isLast = index == crumbs.count - 1
                Button(crumb) { if !isLast, index < Self.levels.count { onCrumb(Self.levels[index]) } }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: isLast ? .semibold : .regular))
                    .foregroundStyle(isLast ? theme.textHi : theme.textMid)
                    .disabled(isLast)
            }
        }
    }
}

// MARK: - Left rail (title · legend · hint)

struct ConstellationRail: View {
    let theme: Theme

    private static let legend: [(GitStatus, String)] = [
        (.clean, "clean"), (.dirty, "dirty"), (.ahead, "ahead"),
        (.behind, "behind"), (.untracked, "untracked"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("CONSTELLATION")
                .font(.system(size: 10, weight: .semibold)).tracking(1.5)
                .foregroundStyle(theme.textDim)

            VStack(alignment: .leading, spacing: 8) {
                Text("GIT STATUS")
                    .font(.system(size: 9, weight: .semibold)).tracking(1.2)
                    .foregroundStyle(theme.textDim)
                ForEach(Self.legend, id: \.0) { status, name in
                    HStack(spacing: 8) {
                        Circle().fill(theme.statusColor(status)).frame(width: 8, height: 8)
                        Text(name).font(.system(size: 11)).foregroundStyle(theme.textMid)
                    }
                }
            }

            Spacer()

            Text("Click a star to dive in. ‹ Back or the breadcrumb to zoom out.")
                .font(.system(size: 11))
                .foregroundStyle(theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 236, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.rail)
    }
}

// MARK: - Frosted Back pill

struct BackPill: View {
    let theme: Theme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Back", systemImage: "chevron.left")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.textHi)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(theme.accentSoft, lineWidth: 1))
        .accessibilityLabel("Back")
    }
}

// MARK: - Full Disk Access hint banner

/// Slim, dismissible banner shown when live refresh needs Full Disk Access (P3-D, FDA hint):
/// FSEvents won't fire on TCC-protected roots without it, so the constellation paints the last scan
/// but never updates on its own. The scan still works, so this nudges rather than blocks. UI glue
/// (the NSWorkspace deep link can't be unit-tested → proven via /verify); *whether* it shows is
/// decided by the tested `HubDataStore` + `FullDiskAccessHint`.
struct FullDiskAccessBanner: View {
    let theme: Theme
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.statusColor(.dirty))
            VStack(alignment: .leading, spacing: 1) {
                Text("Live updates need Full Disk Access")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textHi)
                Text("Your projects still load, but the constellation won't refresh on its own until you grant access.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMid)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button("Open Settings…") { Self.openFullDiskAccessSettings() }
                .buttonStyle(.borderless)
                .foregroundStyle(theme.gold)
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.textDim)
            .accessibilityLabel("Dismiss Full Disk Access notice")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(theme.statusColor(.dirty).opacity(0.12))
    }

    /// Deep-links to System Settings → Privacy & Security → Full Disk Access.
    static func openFullDiskAccessSettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Hub fallback (non-generic: generic types can't hold stored statics)

private enum HubFallback {
    /// Just the central "All Projects" star — shown under the scanning indicator before results land.
    static let loading = ConstellationLayout().buildHub(
        clusters: [], hub: HubInput(name: HubGeometry.hubName, center: HubGeometry.center))
}

// MARK: - Scanning indicator (shown over the empty hub during the first live scan)

struct ScanningIndicator: View {
    let theme: Theme

    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(theme.textMid)
            Text("Scanning projects…")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.textMid)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.accentSoft, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scanning projects")
    }
}

#Preview("Hub") {
    ConstellationShell(theme: .dark)
        .frame(width: 1040, height: 720)
}

#Preview("Light") {
    ConstellationShell(theme: .light)
        .frame(width: 1040, height: 720)
}
