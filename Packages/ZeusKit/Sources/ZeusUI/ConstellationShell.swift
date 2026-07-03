import SwiftUI
import AppKit
import ZeusDomain

/// The constellation window (SPEC §7): a 54px topbar, a body of { 236px rail | zoom canvas }, and
/// a bottom panel that is the PTY terminal on hub/worktree levels or the Changes panel on the
/// branch tree. Owns the `NavigationStore` (UDF) and the active `Theme`; the terminal pane is
/// injected via a `@ViewBuilder` so this layer stays decoupled from `ZeusTerminal` (SwiftTerm).
public struct ConstellationShell<TerminalContent: View>: View {
    @State private var store: NavigationStore
    /// Ephemeral theme for the storeless paths (previews / ZoomSpike / `-uiTestFixtures`). When a
    /// `settings` store is injected the *persisted* theme wins (see `theme`) so the sun/moon toggle
    /// survives relaunch (P7-D).
    @State private var localTheme: Theme
    /// The shared settings store (P7-D): drives the persisted theme + gradient. Optional so the
    /// preview/fixture paths render without a store.
    @State private var settings: SettingsStore?
    /// The four level stores. The app injects live-git stores; previews / ZoomSpike / `-uiTestFixtures`
    /// inject sample-backed *fixture* stores (see `ConstellationShell.sample`). When a store is nil the
    /// shell paints a neutral empty level — it never reaches for a specific fixture itself (slice 7(b)).
    @State private var hubData: HubDataStore?
    @State private var orbitData: WorktreeOrbitStore?
    @State private var treeData: CommitTreeStore?
    @State private var diffData: CommitDiffStore?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// The terminal pane is built *per working directory* (SPEC §2.6, §7): the shell hands the
    /// current cwd to this builder so the PTY opens inside the dived-into repo. Injected as a
    /// closure so this layer stays decoupled from `ZeusTerminal` (SwiftTerm).
    private let terminalContent: (URL) -> TerminalContent

    public init(theme: Theme = .dark,
                store: NavigationStore = NavigationStore(),
                settings: SettingsStore? = nil,
                hubData: HubDataStore? = nil,
                orbitData: WorktreeOrbitStore? = nil,
                treeData: CommitTreeStore? = nil,
                diffData: CommitDiffStore? = nil,
                @ViewBuilder terminalContent: @escaping (URL) -> TerminalContent) {
        _store = State(initialValue: store)
        _localTheme = State(initialValue: theme)
        _settings = State(initialValue: settings)
        _hubData = State(initialValue: hubData)
        _orbitData = State(initialValue: orbitData)
        _treeData = State(initialValue: treeData)
        _diffData = State(initialValue: diffData)
        self.terminalContent = terminalContent
    }

    private var presenter: ConstellationPresenter { ConstellationPresenter(state: store.state) }

    /// The active theme: the persisted preference when a settings store is present, else the
    /// ephemeral local one. Reading `settings.theme` (an `@Observable`) re-renders on toggle (UDF).
    private var theme: Theme {
        if let settings { return Theme(mode: settings.theme) }
        return localTheme
    }

    /// The sun/moon toggle intent — persists through the store when present, else flips locally.
    private func toggleTheme() {
        if let settings { settings.toggleTheme() } else { localTheme = localTheme.toggled }
    }

    /// The cwd the PTY should open in for the current level (derived, not stored).
    private var terminalWorkingDirectory: URL {
        presenter.terminalWorkingDirectory(home: FileManager.default.homeDirectoryForCurrentUser)
    }

    public var body: some View {
        VStack(spacing: 0) {
            ConstellationTopBar(presenter: presenter, theme: theme,
                                onCrumb: { store.dispatch(.backTo($0)) },
                                onToggleTheme: { toggleTheme() })
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
        // Returning to the foreground may mean the user just granted Full Disk Access in System
        // Settings — re-probe so the hint banner clears without requiring an app relaunch.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await hubData?.recheckFullDiskAccessHint() } }
        }
        // Diving into a repo sets `projectPath` (at phaseAdvance); load that repo's real worktrees
        // so the orbit level reflects the dived-into repo rather than the sample fixture.
        .onChange(of: store.state.projectPath) { _, path in
            guard let path else { return }
            orbitData?.load(repoPath: URL(fileURLWithPath: path))
        }
        // Entering the tree level loads the dived-into worktree's branch history (fires on every
        // dive-in, incl. re-diving the same branch, so its commits/HEAD stay fresh).
        .onChange(of: store.state.view) { _, view in
            guard view == .tree, let path = store.state.projectPath,
                  let branch = store.state.worktreeBranch else { return }
            treeData?.load(repoPath: URL(fileURLWithPath: path), branch: branch)
        }
        // The tip is only known once the history loads — land HEAD/selected on it then.
        .onChange(of: treeData?.tip) { _, tip in
            if let tip { store.dispatch(.branchTipResolved(tip)) }
        }
        // Selecting a commit on the tree level (incl. the tip landing via .branchTipResolved) loads
        // that commit's real changed files + diff so the Changes panel reflects the selection.
        .onChange(of: store.state.selected) { _, sha in
            guard store.state.view == .tree, !sha.isEmpty,
                  let path = store.state.projectPath else { return }
            diffData?.load(repoPath: URL(fileURLWithPath: path), sha: sha)
        }
    }

    /// Hub source: the store's hub once loaded, else a neutral empty hub (just the central star) —
    /// shown while a real store scans, or whenever no store is injected at all.
    private var displayHub: ConstellationHub {
        hubData?.hub ?? HubFallback.loading
    }

    /// True while a real store is injected and its first scan hasn't completed.
    private var isScanning: Bool { hubData != nil && hubData?.hub == nil }

    /// Worktree source: the store's orbits once loaded, else a neutral empty orbit (just the repo
    /// star at the canonical center) — shown while loading or when no store is injected.
    private var displayOrbits: ConstellationOrbits {
        orbitData?.orbits ?? .empty(center: WorktreeOrbitStore.defaultCenter)
    }

    /// Branch-tree source: the store's tree once loaded, else a neutral empty tree — shown while
    /// loading or when no store is injected.
    private var displayTree: ConstellationTree {
        treeData?.tree ?? ConstellationTree(nodes: [], edges: [])
    }

    /// Changes-panel source: the store's diff once loaded, else a neutral empty diff for the selected
    /// sha (panel shows "No changes.") — shown while loading or when no store is injected.
    private var displayDiff: CommitDiff {
        diffData?.diff ?? CommitDiff(sha: store.state.selected, files: [], patch: "")
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
                // The tip is unknown at dive time; reset it to empty and let the tree store resolve it
                // from the loaded history (.branchTipResolved), which lands HEAD/selected on the tip.
                // Fixture stores publish their seeded tip the same way, so the flow is identical.
                store.dispatch(.dive(to: .tree, focal: sat.point,
                                     context: DiveContext(worktreeBranch: sat.branch, tip: "")))
            }
        case .tree:
            TreeLevelView(tree: displayTree,
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
            // Open the PTY in the dived-into repo (else home at the hub). `.id(cwd)` gives the
            // terminal a per-directory identity so SwiftTerm relaunches the shell in the new cwd
            // when the user dives in/out — `updateNSView` alone can't re-root a running PTY.
            let cwd = terminalWorkingDirectory
            ZStack {
                theme.panel
                terminalContent(cwd).id(cwd)
            }
            .frame(height: 196)
        case .changes:
            // Commit header comes from the displayed tree; the diff comes from the injected
            // `CommitDiffStore` (live git in the app, sample-backed in previews / `-uiTestFixtures`).
            let selected = displayTree.nodes.first { $0.id == store.state.selected }
            ChangesPanelView(commit: selected,
                             diff: displayDiff,
                             isHead: presenter.selectedIsHead,
                             theme: theme,
                             onCheckout: { store.dispatch(.checkout($0)) })
                .frame(height: 232)
        }
    }
}

// Convenience: a sample-backed shell with the placeholder terminal (previews / `-uiTestFixtures`).
extension ConstellationShell where TerminalContent == TerminalPlaceholder {
    @MainActor
    public static func sample(theme: Theme = .dark) -> ConstellationShell {
        sample(theme: theme) { _ in TerminalPlaceholder() }
    }
}

// MARK: - Sample-backed shell (slice 7(b))

extension ConstellationShell {
    /// Builds the shell over *fixture* stores seeded from `SampleConstellationData`, so the whole
    /// constellation renders without a scan / git CLI / Full Disk Access. This is where the sample
    /// lives now — the shell itself only ever sees stores, never a specific fixture. Used by the
    /// SwiftUI previews, the ZoomSpike harness, and the deterministic `-uiTestFixtures` UI-test build.
    @MainActor
    public static func sample(theme: Theme = .dark,
                              @ViewBuilder terminalContent: @escaping (URL) -> TerminalContent) -> ConstellationShell {
        ConstellationShell(
            theme: theme,
            hubData: HubDataStore(fixtureHub: SampleConstellationData.hub),
            orbitData: WorktreeOrbitStore(fixtureOrbits: SampleConstellationData.orbits),
            treeData: CommitTreeStore(fixtureTree: SampleConstellationData.tree,
                                      fixtureTip: SampleConstellationData.tipSHA),
            diffData: CommitDiffStore(fixtureDiff: SampleConstellationData.diff(forSHA:)),
            terminalContent: terminalContent)
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
    ConstellationShell.sample(theme: .dark)
        .frame(width: 1040, height: 720)
}

#Preview("Light") {
    ConstellationShell.sample(theme: .light)
        .frame(width: 1040, height: 720)
}
