import SwiftUI
import ZeusDomain

/// Design tokens for the constellation UI (SPEC §7 / `Design/HANDOFF.md`). Two themes ship —
/// the moon/sun topbar toggle switches them. Tokens are exposed as `#RRGGBB` strings (the
/// canonical, testable form) with thin `Color` accessors layered on the existing `Color(hex:)`.
/// Git status is the *only* semantic color scale; project types are never color-coded.
public enum Theme: String, Sendable, CaseIterable, Hashable {
    case dark, light

    /// The opposite theme — drives the topbar sun/moon toggle.
    public var toggled: Theme { self == .dark ? .light : .dark }

    // MARK: - Domain bridge (P7-D)

    /// Maps from the pure domain `ThemeMode` persisted in `ZeusSettings`.
    public init(mode: ThemeMode) { self = mode == .dark ? .dark : .light }

    /// The pure domain representation, for persisting the user's choice.
    public var mode: ThemeMode { self == .dark ? .dark : .light }

    // MARK: - Surface & text tokens (dark = SPEC §7; light = static frame ③)

    public var appBackgroundHex: String { self == .dark ? "#0A0B10" : "#F6F7FB" }
    public var railHex: String          { self == .dark ? "#0C0E13" : "#FFFFFF" }
    public var panelHex: String         { self == .dark ? "#080A0E" : "#FFFFFF" }
    public var elevatedHex: String      { self == .dark ? "#0E1117" : "#F1F3F7" }
    public var controlHex: String       { self == .dark ? "#14171F" : "#F1F3F7" }
    public var accentSoftHex: String    { self == .dark ? "#2A3350" : "#E4E7EE" }
    // Borders are translucent white over the dark surfaces (Design/HANDOFF "Color — dark theme"):
    // hairline = rgba(255,255,255,0.06) = #FFFFFF0F, control = rgba(255,255,255,0.08) = #FFFFFF14.
    // Light keeps the opaque frame-③ greys (a translucent-white line is invisible on a light surface).
    public var hairlineHex: String      { self == .dark ? "#FFFFFF0F" : "#E9EBF1" }
    public var controlBorderHex: String { self == .dark ? "#FFFFFF14" : "#E4E7EE" }
    public var textHiHex: String        { self == .dark ? "#E7EAF2" : "#1A1D24" }
    public var textMidHex: String       { self == .dark ? "#9AA3B8" : "#4B5563" }
    public var textDimHex: String       { self == .dark ? "#646C80" : "#9AA1AD" }
    public var goldHex: String          { self == .dark ? "#F5C451" : "#E0A21A" }

    // MARK: - Constellation map palette (line + label hues from the layout algorithm, not the
    // status scale). Dark values are the prototype's exact rgba literals; light values are muted
    // to stay legible on the light frame. Opacities are applied at the call site (edges .15/.06,
    // orbit rings .18, repo labels .62) — these tokens carry only the base hue.

    /// Constellation / orbit lines — `rgba(150,170,255, α)` in the prototype.
    public var constellationLineHex: String { self == .dark ? "#96AAFF" : "#7C8BB8" }
    /// Cluster type labels above each group — `#CFD5E6`.
    public var clusterLabelHex: String      { self == .dark ? "#CFD5E6" : "#4B5563" }
    /// Repo name labels under each star — `rgba(180,190,215, .62)`.
    public var repoLabelHex: String         { self == .dark ? "#B4BED7" : "#6B7280" }
    /// Worktree/planet labels on the solar-system level — `#AEB6C8`.
    public var orbitLabelHex: String        { self == .dark ? "#AEB6C8" : "#4B5563" }

    // MARK: - Git status — the only semantic color scale (drives node fill)

    public func statusHex(_ status: GitStatus) -> String {
        switch self {
        case .dark:
            switch status {
            case .clean:     return "#35D08B"
            case .dirty:     return "#F5A623"
            case .ahead:     return "#6E8BFF"
            case .behind:    return "#FF6B6B"
            case .untracked: return "#8B93A7"
            }
        case .light:
            switch status {
            case .clean:     return "#1FA971"
            case .dirty:     return "#D6841A"
            case .ahead:     return "#3457C5"
            case .behind:    return "#E0524F"
            case .untracked: return "#9AA1AD"
            }
        }
    }

    /// Shape-distinct SF Symbol per status, drawn on nodes under Differentiate Without Color so git
    /// status is legible without relying on hue (WCAG 1.4.1). Theme-independent (shape, not color).
    public static func statusSymbol(_ status: GitStatus) -> String {
        switch status {
        case .clean:     return "checkmark"
        case .dirty:     return "pencil"
        case .ahead:     return "arrow.up"
        case .behind:    return "arrow.down"
        case .untracked: return "questionmark"
        }
    }

    // MARK: - Branch lanes (branch-tree level), colored by branch name

    /// `main` = Asteris gold, `develop` = indigo, `feature/*` = violet, `fix/*` = cyan. The
    /// `auth`/`cache` aliases match the prototype's short lane keys (see `SampleConstellationData`).
    public static func laneHex(forBranch branch: String) -> String {
        switch branch {
        case "main":    return "#F5C451"
        case "develop": return "#6E8BFF"
        default:
            if branch.hasPrefix("feature/") || branch == "auth"  { return "#B98BFF" }
            if branch.hasPrefix("fix/")     || branch == "cache" { return "#57E0FF" }
            return "#9AA3B8"   // neutral fallback
        }
    }

    // MARK: - Diff syntax palette (Design/HANDOFF "Color — diff / file status")

    // Added / deleted lines get tinted text over a 10% status-hue background (0.10·255 ≈ 0x1A).
    // Context, hunk headers, and file headers are the greys from the prototype's rendered diff.
    // Light values reuse the light status scale so tints stay legible on the light frame.
    public var diffAddTextHex: String    { self == .dark ? "#7BD4A8" : "#1FA971" }
    public var diffAddBgHex: String      { self == .dark ? "#35D08B1A" : "#1FA9711A" }
    public var diffDelTextHex: String    { self == .dark ? "#FF9D9D" : "#E0524F" }
    public var diffDelBgHex: String      { self == .dark ? "#FF6B6B1A" : "#E0524F1A" }
    public var diffContextHex: String    { self == .dark ? "#AEB6C8" : "#4B5563" }
    public var diffHunkHex: String       { self == .dark ? "#646C80" : "#9AA1AD" }
    public var diffFileHeaderHex: String { self == .dark ? "#7C8597" : "#6B7280" }

    /// Foreground (and optional line-background) color for a classified diff line.
    public func diffStyle(_ kind: DiffLineKind) -> (foreground: Color, background: Color?) {
        switch kind {
        case .fileHeader: return (Color(hex: diffFileHeaderHex), nil)
        case .hunkHeader: return (Color(hex: diffHunkHex), nil)
        case .context:    return (Color(hex: diffContextHex), nil)
        case .addition:   return (Color(hex: diffAddTextHex), Color(hex: diffAddBgHex))
        case .deletion:   return (Color(hex: diffDelTextHex), Color(hex: diffDelBgHex))
        }
    }

    // MARK: - Color accessors (thin passthrough over Color(hex:))

    public var appBackground: Color { Color(hex: appBackgroundHex) }
    public var rail: Color          { Color(hex: railHex) }
    public var panel: Color         { Color(hex: panelHex) }
    public var elevated: Color      { Color(hex: elevatedHex) }
    public var control: Color       { Color(hex: controlHex) }
    public var accentSoft: Color    { Color(hex: accentSoftHex) }
    public var hairline: Color      { Color(hex: hairlineHex) }
    public var controlBorder: Color { Color(hex: controlBorderHex) }
    public var textHi: Color        { Color(hex: textHiHex) }
    public var textMid: Color       { Color(hex: textMidHex) }
    public var textDim: Color       { Color(hex: textDimHex) }
    public var gold: Color          { Color(hex: goldHex) }
    public var constellationLine: Color { Color(hex: constellationLineHex) }
    public var clusterLabel: Color  { Color(hex: clusterLabelHex) }
    public var repoLabel: Color     { Color(hex: repoLabelHex) }
    public var orbitLabel: Color    { Color(hex: orbitLabelHex) }

    public func statusColor(_ status: GitStatus) -> Color { Color(hex: statusHex(status)) }
    public static func laneColor(forBranch branch: String) -> Color { Color(hex: laneHex(forBranch: branch)) }
}
