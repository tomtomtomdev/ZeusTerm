import SwiftUI
import ZeusDomain

/// The fixed 1040×540 stage coordinate space (SPEC §7). Every constellation coordinate — stars,
/// orbits, commits, zoom origins — lives here; the view scales this stage into the canvas. The
/// zoom `scaleEffect` pivots on a focal node expressed as a `UnitPoint`, so the geometry's job is
/// the stage→unit mapping.
public enum StageGeometry {
    public static let width: Double = 1040
    public static let height: Double = 540

    /// Maps a stage-space point to a SwiftUI `UnitPoint` (0…1) for use as a `scaleEffect` anchor.
    public static func unitPoint(for point: StagePoint) -> UnitPoint {
        UnitPoint(x: point.x / width, y: point.y / height)
    }
}
