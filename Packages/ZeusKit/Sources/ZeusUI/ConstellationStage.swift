import SwiftUI
import ZeusDomain

// MARK: - Shared node rendering (SPEC §7: glowing status-colored stars / commit nodes)

/// A glowing star/satellite disc. `ring` draws the white border the hub & repo stars carry.
struct StarDisc: View {
    let color: Color
    let diameter: Double
    var ring: Bool = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
            // Glow ≈ SPEC `0 0 {size*2} {size*0.6} {color}66` — a soft halo the size of the star.
            .shadow(color: color.opacity(0.55), radius: diameter, x: 0, y: 0)
            .overlay {
                if ring {
                    Circle().stroke(.white, lineWidth: 1.5).frame(width: diameter, height: diameter)
                }
            }
    }
}

/// A commit node. HEAD gets a 15px disc + white ring; a selected non-HEAD node gets a faint ring.
struct CommitDot: View {
    let color: Color
    let isHead: Bool
    let isSelected: Bool

    var body: some View {
        let d: Double = isHead ? 15 : 11
        Circle()
            .fill(color)
            .frame(width: d, height: d)
            .shadow(color: color.opacity(0.5), radius: isHead ? 8 : 5)
            .overlay {
                if isHead {
                    Circle().stroke(.white, lineWidth: 2).frame(width: d + 6, height: d + 6)
                } else if isSelected {
                    Circle().stroke(.white.opacity(0.85), lineWidth: 1.5).frame(width: d + 6, height: d + 6)
                }
            }
    }
}

// MARK: - Stage container — fits the 1040×540 stage and applies the live zoom transform

/// Centers the fixed-size stage in the available canvas and applies the phase-driven zoom
/// (scale about the focal node + fade). Each phase animates with its OWN curve (SPEC §7) — and
/// the `enter` phase is an INSTANT set so the incoming level snaps pre-scaled to the focal node
/// and then unfolds during `idle`. Sharing one animation across all phases animated the
/// leave→enter scale jump, which made dive-in expand from the wrong spot.
///
/// The zoom **pivot snaps, it never tweens.** Prototype parity (Design/ZeusTerm-Live.dc.html lines
/// 335/340/342): the CSS transitions only `transform` and `opacity` — `transform-origin` is never
/// in the transition list. SwiftUI bundles the pivot into `scaleEffect(_:anchor:)`, so the shared
/// `.animation(value: phase)` would interpolate the anchor across the cross-transition focal jump;
/// diving into an off-center node then reads as a sideways PAN while zooming in. We mirror the
/// prototype by holding the anchor in `@State` and committing it in a non-animated transaction, so
/// only scale + opacity ride the phase curve.
struct ConstellationStage<Content: View>: View {
    let presenter: ConstellationPresenter
    @ViewBuilder var content: Content

    /// The live zoom pivot. Snapped (never animated) via `commitAnchor`; the default matches the
    /// reducer's resting origin and is corrected on first appearance by the `initial` onChange.
    @State private var anchor: UnitPoint = .center

    var body: some View {
        GeometryReader { geo in
            let fit = min(geo.size.width / StageGeometry.width, geo.size.height / StageGeometry.height)
            content
                .frame(width: StageGeometry.width, height: StageGeometry.height)
                .scaleEffect(presenter.transition.scale, anchor: anchor)
                .opacity(presenter.transition.opacity)
                .animation(stageAnimation, value: presenter.state.phase)
                .scaleEffect(fit)
                .frame(width: geo.size.width, height: geo.size.height)
                .onChange(of: presenter.transitionAnchor, initial: true) { _, pivot in
                    commitAnchor(pivot)
                }
        }
    }

    /// Snap the pivot with animation disabled — the SwiftUI equivalent of CSS not transitioning
    /// `transform-origin`. The scale/opacity changes from the same phase update still animate.
    private func commitAnchor(_ pivot: UnitPoint) {
        var snap = Transaction()
        snap.disablesAnimations = true
        withTransaction(snap) { anchor = pivot }
    }

    /// The animation for arriving into the current phase — `nil` (instant) for `enter` and under
    /// Reduce Motion; otherwise the phase's cubic-bézier curve from the pure `StageMotion` policy.
    private var stageAnimation: Animation? {
        guard !presenter.state.reduceMotion,
              let m = StageMotion.arriving(at: presenter.state.phase) else { return nil }
        return .timingCurve(m.easing.c1x, m.easing.c1y, m.easing.c2x, m.easing.c2y, duration: m.duration)
    }
}

// MARK: - Level 1 — Hub: clustered repo stars joined by faint constellation lines

struct HubLevelView: View {
    let hub: ConstellationHub
    let theme: Theme
    let onSelectRepo: (StarNode) -> Void

    var body: some View {
        ZStack {
            Canvas { ctx, _ in
                for edge in hub.edges {
                    var path = Path()
                    path.move(to: CGPoint(x: edge.from.x, y: edge.from.y))
                    path.addLine(to: CGPoint(x: edge.to.x, y: edge.to.y))
                    ctx.stroke(path,
                               with: .color(theme.textDim.opacity(edge.dim ? 0.10 : 0.20)),
                               lineWidth: 1)
                }
            }

            ForEach(hub.labels, id: \.text) { label in
                Text(label.text.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(theme.textDim)
                    .position(x: label.point.x, y: label.point.y)
            }

            ForEach(hub.stars) { star in
                StarDisc(color: star.isHub ? theme.gold : theme.statusColor(star.status ?? .clean),
                         diameter: star.size,
                         ring: star.isHub)
                    .frame(width: 34, height: 34)        // generous invisible hit target
                    .contentShape(Rectangle())
                    .position(x: star.point.x, y: star.point.y)
                    .onTapGesture { if !star.isHub { onSelectRepo(star) } }
                    .accessibilityLabel(starLabel(star))
                    .accessibilityIdentifier(star.isHub ? "hubStar.hub" : "hubStar.\(star.name)")
                    .accessibilityAddTraits(star.isHub ? [] : .isButton)

                // Each repo star wears its project name (the cluster-type label names the group,
                // not the project). The hub stays unlabeled here — it's visually distinct already.
                // a11y lives on the disc above, so the label is hidden to avoid a duplicate read.
                if !star.isHub {
                    Text(star.name)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(theme.textDim)
                        .fixedSize()
                        .position(x: star.point.x, y: star.point.y + 11)
                        .allowsHitTesting(false)   // decorative — never steal a tap from a star
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(width: StageGeometry.width, height: StageGeometry.height)
    }

    private func starLabel(_ star: StarNode) -> String {
        guard let status = star.status else { return "\(star.name), monorepo hub" }
        return "\(star.name), \(status)"
    }
}

// MARK: - Level 2 — Worktrees: satellites on dashed elliptical orbit rings

struct OrbitLevelView: View {
    let orbits: ConstellationOrbits
    let theme: Theme
    let onSelectWorktree: (SatelliteNode) -> Void

    var body: some View {
        ZStack {
            Canvas { ctx, _ in
                for ring in orbits.rings {
                    let rect = CGRect(x: ring.center.x - ring.rx, y: ring.center.y - ring.ry,
                                      width: ring.rx * 2, height: ring.ry * 2)
                    ctx.stroke(Path(ellipseIn: rect),
                               with: .color(theme.textDim.opacity(0.30)),
                               style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
                }
            }

            StarDisc(color: centerColor, diameter: 17, ring: true)
                .shadow(color: centerColor.opacity(0.6), radius: 22)
                .position(x: orbits.center.point.x, y: orbits.center.point.y)
                .accessibilityLabel(centerLabel(orbits.center))

            if !orbits.center.name.isEmpty {
                Text(orbits.center.name)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.textHi)
                    .fixedSize()
                    .position(x: orbits.center.point.x, y: orbits.center.point.y + 28)
                    .accessibilityHidden(true)
            }

            ForEach(orbits.satellites) { sat in
                StarDisc(color: theme.statusColor(sat.status), diameter: sat.size)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
                    .position(x: sat.point.x, y: sat.point.y)
                    .onTapGesture { onSelectWorktree(sat) }
                    .accessibilityLabel(satelliteLabel(sat))
                    .accessibilityIdentifier("worktree.\(sat.branch)")
                    .accessibilityAddTraits(.isButton)

                Text(sat.branch)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(theme.textMid)
                    .fixedSize()
                    .frame(width: 120, alignment: sat.labelOnRight ? .leading : .trailing)
                    .position(x: sat.labelPoint.x + (sat.labelOnRight ? 60 : -60),
                              y: sat.labelPoint.y)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: StageGeometry.width, height: StageGeometry.height)
    }

    /// The repo star's color mirrors its root status (the main worktree), defaulting to clean when
    /// the repo is still loading or has no worktrees — continuous with the status-colored star the
    /// user clicked at the Hub. The white ring + size + glow keep it distinct from the satellites.
    private var centerColor: Color {
        theme.statusColor(orbits.center.status ?? .clean)
    }

    /// Plain `String` (not a `LocalizedStringKey`) so the `GitStatus` reads as its case name.
    private func satelliteLabel(_ sat: SatelliteNode) -> String {
        "\(sat.name), \(sat.branch), \(sat.status)"
    }

    /// Names the central repo star and reports its status; falls back to "repository" before the
    /// repo name is known (the brief loading frame).
    private func centerLabel(_ center: OrbitCenter) -> String {
        let name = center.name.isEmpty ? "repository" : center.name
        guard let status = center.status else { return "\(name), repository" }
        return "\(name), repository, \(status)"
    }
}

// MARK: - Level 3 — Branch tree: a vertical commit constellation (newest on top)

struct TreeLevelView: View {
    let tree: ConstellationTree
    let head: String
    let selected: String
    let theme: Theme
    let onSelect: (String) -> Void
    let onCheckout: (String) -> Void

    var body: some View {
        ZStack {
            // Faint left time axis: LATEST ▼ … OLDEST.
            axis

            Canvas { ctx, _ in
                for edge in tree.edges {
                    var path = Path()
                    path.move(to: CGPoint(x: edge.from.x, y: edge.from.y))
                    path.addLine(to: CGPoint(x: edge.to.x, y: edge.to.y))
                    ctx.stroke(path,
                               with: .color(Theme.laneColor(forBranch: edge.branch).opacity(0.55)),
                               lineWidth: 2)
                }
            }

            ForEach(lanePills, id: \.branch) { pill in
                Text(pill.branch)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.laneColor(forBranch: pill.branch).opacity(0.18),
                                in: Capsule())
                    .foregroundStyle(Theme.laneColor(forBranch: pill.branch))
                    .fixedSize()
                    .position(x: pill.point.x, y: pill.point.y - 24)
                    .accessibilityHidden(true)
            }

            ForEach(tree.nodes) { node in
                let isHead = node.id == head
                CommitDot(color: Theme.laneColor(forBranch: node.branch),
                          isHead: isHead,
                          isSelected: !isHead && node.id == selected)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
                    .position(x: node.point.x, y: node.point.y)
                    .opacity(node.isDim ? 0.3 : 1)
                    .grayscale(node.isDim ? 0.5 : 0)
                    .onTapGesture(count: 2) { onCheckout(node.id) }
                    .onTapGesture { onSelect(node.id) }
                    .accessibilityLabel(commitLabel(node, isHead: isHead))
                    .accessibilityIdentifier("commit.\(node.id)")
                    .accessibilityAddTraits(.isButton)

                // The commit message reads better than a raw sha at a glance; the full sha still
                // lives in the a11y label and the Changes panel. Capped + tail-truncated so a long
                // subject can't sprawl across the lane.
                Text(node.summary)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(theme.textDim)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 240)
                    .position(x: node.point.x, y: node.point.y + 18)
                    .opacity(node.isDim ? 0.3 : 1)
                    .allowsHitTesting(false)   // the 240pt label must not cover a neighbor node's tap
                    .accessibilityHidden(true)
            }
        }
        .frame(width: StageGeometry.width, height: StageGeometry.height)
    }

    private var axis: some View {
        ZStack {
            Rectangle()
                .fill(theme.textDim.opacity(0.25))
                .frame(width: 1, height: 440)
                .position(x: 40, y: 270)
            Text("LATEST ▼").font(.system(size: 9, weight: .semibold)).tracking(1)
                .foregroundStyle(theme.textDim)
                .position(x: 52, y: 44)
            Text("OLDEST").font(.system(size: 9, weight: .semibold)).tracking(1)
                .foregroundStyle(theme.textDim)
                .position(x: 48, y: 500)
        }
        .accessibilityHidden(true)
    }

    /// The newest (highest-rank) commit per branch carries the lane name pill.
    private var lanePills: [(branch: String, point: StagePoint)] {
        Dictionary(grouping: tree.nodes, by: \.branch)
            .compactMap { branch, nodes -> (branch: String, point: StagePoint)? in
                guard let top = nodes.max(by: { $0.rank < $1.rank }) else { return nil }
                return (branch, top.point)
            }
            .sorted { $0.branch < $1.branch }
    }

    private func commitLabel(_ node: CommitNode, isHead: Bool) -> String {
        let head = isHead ? ", HEAD" : ""
        return "\(node.id), \(node.summary), \(node.branch)\(head)"
    }
}
