import Foundation

/// Single source of truth for the hub level's stage-space layout (SPEC §7 / prototype geometry).
/// Both the real `HubModelBuilder` and the sample fixtures place clusters at these slots, and the
/// empty-hub fallbacks share this center/name — so the layout lives in exactly one place and can't
/// drift between real and sample data.
public enum HubGeometry {
    /// The central hub star's stage position.
    public static let center = StagePoint(x: 512, y: 252)

    /// The default hub label for real scans ("All Projects"); the sample uses its own monorepo name.
    public static let hubName = "All Projects"

    /// Fixed stage-space slot per type; `other` fills the bottom-center gap below the hub.
    public static func slot(for type: RepoType) -> (center: StagePoint, spread: Double) {
        switch type {
        case .frontend: (StagePoint(x: 205, y: 148), 70)
        case .backend:  (StagePoint(x: 498, y: 118), 82)
        case .ios:      (StagePoint(x: 788, y: 158), 56)
        case .macos:    (StagePoint(x: 862, y: 342), 52)
        case .mobile:   (StagePoint(x: 608, y: 408), 58)
        case .scripts:  (StagePoint(x: 218, y: 392), 64)
        case .other:    (StagePoint(x: 430, y: 472), 60)
        }
    }
}
