import Testing
import Foundation
@testable import ZeusDomain

struct SeededGeneratorTests {

    /// Pins the Swift port to the design prototype's `mulberry32(1337)` sequence
    /// (values captured from the reference JS) so domain layout matches the design.
    @Test func reproducesMulberry32ReferenceSequence() {
        var rng = SeededGenerator(seed: 1337)
        let expected = [
            0.184411832597107, 0.189989251317456, 0.810471992241219,
            0.643748822156340, 0.430774615611881, 0.381045897025615,
        ]
        for value in expected {
            #expect(abs(rng.next() - value) < 1e-12)
        }
    }

    @Test func isDeterministicPerSeedAndInRange() {
        var a = SeededGenerator(seed: 1337)
        var b = SeededGenerator(seed: 1337)
        var other = SeededGenerator(seed: 99)
        let first = a.next()
        #expect(first == b.next())          // same seed → same sequence
        #expect(first != other.next())      // different seed → different value
        #expect(first >= 0 && first < 1)    // normalized to [0, 1)
    }
}
