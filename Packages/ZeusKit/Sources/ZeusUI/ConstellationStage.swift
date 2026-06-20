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
/// (scale about the focal node + fade). Exact per-phase easing/durations are refined in the
/// S2ZoomSpike / `/verify`; the reducer already pins the state transitions.
struct ConstellationStage<Content: View>: View {
    let presenter: ConstellationPresenter
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            let fit = min(geo.size.width / StageGeometry.width, geo.size.height / StageGeometry.height)
            content
                .frame(width: StageGeometry.width, height: StageGeometry.height)
                .scaleEffect(presenter.transition.scale, anchor: presenter.transitionAnchor)
                .opacity(presenter.transition.opacity)
                .animation(presenter.state.reduceMotion ? nil
                           : .timingCurve(0.16, 1, 0.3, 1, duration: 0.5),
                           value: presenter.state.phase)
                .scaleEffect(fit)
                .frame(width: geo.size.width, height: geo.size.height)
        }
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
                    .accessibilityAddTraits(star.isHub ? [] : .isButton)
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

            StarDisc(color: theme.gold, diameter: 17, ring: true)
                .shadow(color: theme.gold.opacity(0.6), radius: 22)
                .position(x: orbits.center.x, y: orbits.center.y)
                .accessibilityLabel("repository")

            ForEach(orbits.satellites) { sat in
                StarDisc(color: theme.statusColor(sat.status), diameter: sat.size)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
                    .position(x: sat.point.x, y: sat.point.y)
                    .onTapGesture { onSelectWorktree(sat) }
                    .accessibilityLabel(satelliteLabel(sat))
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

    /// Plain `String` (not a `LocalizedStringKey`) so the `GitStatus` reads as its case name.
    private func satelliteLabel(_ sat: SatelliteNode) -> String {
        "\(sat.name), \(sat.branch), \(sat.status)"
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
                    .accessibilityAddTraits(.isButton)

                Text(node.id)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(theme.textDim)
                    .position(x: node.point.x, y: node.point.y + 18)
                    .opacity(node.isDim ? 0.3 : 1)
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
