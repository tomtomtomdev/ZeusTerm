import Testing
import SwiftUI
import ZeusDomain
@testable import ZeusUI

/// The stage is a fixed 1040×540 coordinate space (SPEC §7); all node/orbit/commit coords live
/// in it. The zoom `scaleEffect` needs its focal anchor as a `UnitPoint` (0…1), so the geometry's
/// only job is the stage→unit mapping. Evident data: center maps to (0.5, 0.5), corners to the box.
struct StageGeometryTests {

    @Test func stageHasTheSpecSize() {
        #expect(StageGeometry.width == 1040)
        #expect(StageGeometry.height == 540)
    }

    @Test func centerMapsToTheUnitCenter() {
        let center = StagePoint(x: 520, y: 270)
        #expect(StageGeometry.unitPoint(for: center) == UnitPoint(x: 0.5, y: 0.5))
    }

    @Test func cornersMapToTheUnitBox() {
        #expect(StageGeometry.unitPoint(for: StagePoint(x: 0, y: 0)) == UnitPoint(x: 0, y: 0))
        #expect(StageGeometry.unitPoint(for: StagePoint(x: 1040, y: 540)) == UnitPoint(x: 1, y: 1))
    }
}
