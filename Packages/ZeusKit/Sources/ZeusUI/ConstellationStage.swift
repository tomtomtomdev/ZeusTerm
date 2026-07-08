import SwiftUI
import ZeusDomain

// MARK: - Shared node rendering (SPEC §7: glowing status-colored stars / commit nodes)

/// The keyboard-focus cursor: a dashed ring drawn AROUND a node when it holds keyboard focus. Dashed
/// (vs the solid HEAD/selected rings) so "focus cursor" reads distinctly from "git state" (SPEC §7
/// keyboard accessibility). Sized a touch larger than the node it wraps.
struct FocusRing: View {
    let diameter: Double

    var body: some View {
        Circle()
            .strokeBorder(.white, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
            .frame(width: diameter + 12, height: diameter + 12)
    }
}

/// A small shape-distinct status badge shown beside a node under Differentiate Without Color, so git
/// status is legible without relying on hue (WCAG 1.4.1). Decorative — status is already in the node's
/// VoiceOver label, so this is `accessibilityHidden`.
struct StatusGlyphBadge: View {
    let status: GitStatus
    let theme: Theme

    var body: some View {
        Image(systemName: Theme.statusSymbol(status))
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(theme.textHi)
            .padding(2)
            .background(theme.appBackground.opacity(0.85), in: Circle())
            .overlay(Circle().stroke(theme.textHi.opacity(0.5), lineWidth: 0.5))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// A glowing star/satellite disc. `ring` draws the white border the hub & repo stars carry;
/// `focused` adds the dashed keyboard-focus cursor.
struct StarDisc: View {
    let color: Color
    let diameter: Double
    var ring: Bool = false
    var focused: Bool = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
            // Glow ≈ SPEC `0 0 {size*2} {size*0.6} {color}66` — a soft halo the size of the star.
            // `{color}66` = 0x66/0xFF ≈ 0.40 alpha.
            .shadow(color: color.opacity(0.40), radius: diameter, x: 0, y: 0)
            .overlay {
                if ring {
                    Circle().stroke(.white, lineWidth: 1.5).frame(width: diameter, height: diameter)
                }
            }
            .overlay { if focused { FocusRing(diameter: diameter) } }
    }
}

/// A commit node. HEAD gets a 15px disc + white ring; a selected non-HEAD node gets a faint ring.
struct CommitDot: View {
    let color: Color
    let isHead: Bool
    let isSelected: Bool
    var focused: Bool = false

    var body: some View {
        let d: Double = isHead ? 15 : 11
        Circle()
            .fill(color)
            .frame(width: d, height: d)
            // Node glow ≈ SPEC `{color}66` (≈0.40 alpha).
            .shadow(color: color.opacity(0.40), radius: isHead ? 8 : 5)
            .overlay {
                if isHead {
                    Circle().stroke(.white, lineWidth: 2).frame(width: d + 6, height: d + 6)
                } else if isSelected {
                    Circle().stroke(.white.opacity(0.85), lineWidth: 1.5).frame(width: d + 6, height: d + 6)
                }
            }
            .overlay { if focused { FocusRing(diameter: d) } }
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
    var focusedID: String? = nil
    var differentiateWithoutColor: Bool = false
    var increaseContrast: Bool = false
    let onSelectRepo: (StarNode) -> Void

    var body: some View {
        ZStack {
            Canvas { ctx, _ in
                for edge in hub.edges {
                    var path = Path()
                    path.move(to: CGPoint(x: edge.from.x, y: edge.from.y))
                    path.addLine(to: CGPoint(x: edge.to.x, y: edge.to.y))
                    // SPEC: within-cluster lines rgba(150,170,255,.15), cluster→hub lines .06 (dimmer).
                    let base = edge.dim ? 0.06 : 0.15
                    ctx.stroke(path,
                               with: .color(theme.constellationLine.opacity(increaseContrast ? base * 2 : base)),
                               lineWidth: 1)
                }
            }

            ForEach(hub.labels, id: \.text) { label in
                Text(label.text.uppercased())
                    .font(.system(size: 12.5, weight: .semibold))   // SPEC 12.5px/600
                    .tracking(1.6)                                    // .13em × 12.5 ≈ 1.6
                    .foregroundStyle(theme.clusterLabel)
                    .position(x: label.point.x, y: label.point.y)
            }

            ForEach(Array(hub.stars.enumerated()), id: \.element.id) { index, star in
                // SPEC: hub star is clean-green (#35D08B) like any clean repo — its 16px size + white
                // ring make it distinct, not a unique hue. Hub `status` is nil ⇒ `.clean` ⇒ green.
                StarDisc(color: theme.statusColor(star.status ?? .clean),
                         diameter: star.size,
                         ring: star.isHub,
                         focused: star.id == focusedID)
                    .frame(width: 34, height: 34)        // generous invisible hit target
                    .contentShape(Rectangle())
                    .position(x: star.point.x, y: star.point.y)
                    .onTapGesture { if !star.isHub { onSelectRepo(star) } }
                    .accessibilityLabel(starLabel(star))
                    .accessibilityIdentifier(star.isHub ? "hubStar.hub" : "hubStar.\(star.name)")
                    .accessibilityAddTraits(star.isHub ? [] : .isButton)
                    // Stable VoiceOver order (hub first, then cluster members in layout order).
                    .accessibilitySortPriority(Double(hub.stars.count - index))

                // Differentiate Without Color: a shape badge top-right of each status-colored star.
                if differentiateWithoutColor, !star.isHub, let status = star.status {
                    StatusGlyphBadge(status: status, theme: theme)
                        .position(x: star.point.x + 9, y: star.point.y - 9)
                }

                // Each repo star wears its project name (the cluster-type label names the group,
                // not the project). The hub stays unlabeled here — it's visually distinct already.
                // a11y lives on the disc above, so the label is hidden to avoid a duplicate read.
                if !star.isHub {
                    Text(star.name)
                        .font(.system(size: 9.5, design: .monospaced))   // SPEC 9.5px
                        .foregroundStyle(theme.repoLabel.opacity(0.62))   // rgba(180,190,215,.62)
                        .fixedSize()
                        .position(x: star.point.x, y: star.point.y + star.size / 2 + 11)
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

// MARK: - Level 2 — Worktrees: a side-on solar system (sun + orbiting planets)

/// The worktree level as a tilted, edge-on solar system: the repo is a glowing sun, its worktrees
/// are planets on one flattened orbit each, and depth drives each planet's size/opacity/z so they
/// pass *in front of and behind* the sun as they orbit (Design/HANDOFF §"Worktrees"). The pure
/// geometry lives in `SideOnOrbits.state(of:at:)`; this view just drives it with a clock and paints.
struct OrbitLevelView: View {
    let orbits: SideOnOrbits
    let theme: Theme
    var focusedID: String? = nil
    var reduceMotion: Bool = false
    var differentiateWithoutColor: Bool = false
    var increaseContrast: Bool = false
    let onSelectWorktree: (OrbitPlanet, StagePoint) -> Void

    var body: some View {
        // A monotonic clock advances the orbit; Reduce Motion pauses it and pins every planet to
        // its t=0 frame (the frozen system the handoff specifies).
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            system(at: reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate)
        }
        .frame(width: StageGeometry.width, height: StageGeometry.height)
    }

    private func system(at t: Double) -> some View {
        ZStack {
            orbitRings                 // z 0 — behind everything
            sun.zIndex(100)            // far-side planets (z < 100) duck behind it
            ForEach(Array(orbits.planets.enumerated()), id: \.element.id) { index, planet in
                planetView(planet, index: index, at: t)
            }
        }
        .frame(width: StageGeometry.width, height: StageGeometry.height)
    }

    /// The thin solid orbit ellipses, flattened and rotated as one system by the diagonal tilt.
    private var orbitRings: some View {
        Canvas { ctx, _ in
            let c = orbits.center.point
            ctx.translateBy(x: c.x, y: c.y)               // rotate the whole system about the sun
            ctx.rotate(by: .radians(orbits.tiltRadians))
            ctx.translateBy(x: -c.x, y: -c.y)
            for planet in orbits.planets {
                let rect = CGRect(x: c.x - planet.rx, y: c.y - planet.ry,
                                  width: planet.rx * 2, height: planet.ry * 2)
                ctx.stroke(Path(ellipseIn: rect),
                           with: .color(theme.constellationLine.opacity(increaseContrast ? 0.36 : 0.18)),
                           lineWidth: 1)
            }
        }
    }

    private var sun: some View {
        let c = orbits.center.point
        return ZStack {
            StarDisc(color: centerColor, diameter: 19, ring: true)
                .shadow(color: centerColor.opacity(0.6), radius: 22)
                .position(x: c.x, y: c.y)
                .accessibilityLabel(centerLabel(orbits.center))

            if differentiateWithoutColor, let status = orbits.center.status {
                StatusGlyphBadge(status: status, theme: theme)
                    .position(x: c.x + 12, y: c.y - 12)
            }

            if !orbits.center.name.isEmpty {
                Text("\(orbits.center.name) · main")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.gold)
                    .fixedSize()
                    .position(x: c.x, y: c.y + 28)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private func planetView(_ planet: OrbitPlanet, index: Int, at t: Double) -> some View {
        let s = orbits.state(of: planet, at: t)
        ZStack {
            StarDisc(color: theme.statusColor(planet.status), diameter: s.size,
                     focused: planet.id == focusedID)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
                .position(x: s.point.x, y: s.point.y)
                .onTapGesture { onSelectWorktree(planet, s.point) }
                .accessibilityLabel(planetLabel(planet))
                .accessibilityIdentifier("worktree.\(planet.branch)")
                .accessibilityAddTraits(.isButton)
                .accessibilitySortPriority(Double(orbits.planets.count - index))

            if differentiateWithoutColor {
                StatusGlyphBadge(status: planet.status, theme: theme)
                    .position(x: s.point.x + 8, y: s.point.y - 8)
            }

            Text(planet.branch)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(theme.orbitLabel)                // SPEC #AEB6C8
                .fixedSize()
                .frame(width: 120, alignment: s.labelOnRight ? .leading : .trailing)
                .position(x: s.point.x + (s.labelOnRight ? 73 : -73), y: s.point.y)
                .opacity(min(1, s.depth * 0.9 + 0.06))
                .accessibilityHidden(true)
        }
        .opacity(s.opacity)
        .zIndex(Double(s.zIndex))
    }

    /// The sun mirrors its root status (main worktree), defaulting to clean while the repo loads —
    /// continuous with the status-colored star clicked at the Hub. The white ring + size + glow keep
    /// it distinct from the planets.
    private var centerColor: Color {
        theme.statusColor(orbits.center.status ?? .clean)
    }

    /// Plain `String` (not a `LocalizedStringKey`) so the `GitStatus` reads as its case name.
    private func planetLabel(_ planet: OrbitPlanet) -> String {
        "\(planet.name), \(planet.branch), \(planet.status)"
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
    var focusedID: String? = nil
    var increaseContrast: Bool = false
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
                    // SPEC: edges drawn in lane color at ~82% alpha (`{lane}d0`), 2.2px round caps.
                    ctx.stroke(path,
                               with: .color(Theme.laneColor(forBranch: edge.branch).opacity(increaseContrast ? 0.95 : 0.82)),
                               style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
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
                          isSelected: !isHead && node.id == selected,
                          focused: node.id == focusedID)
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
                    // VoiceOver walks the tree newest→oldest (higher rank = newer = read first), with
                    // x as a tie-break so same-depth sibling-branch commits read left→right instead of
                    // in an undefined order (point.x ∈ 0…1040, scaled small to never cross a rank step).
                    .accessibilitySortPriority(Double(node.rank) - node.point.x / 100_000)

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
