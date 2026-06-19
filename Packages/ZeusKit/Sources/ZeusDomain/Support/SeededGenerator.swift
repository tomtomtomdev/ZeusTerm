import Foundation

/// Deterministic seeded PRNG — a Swift port of the design prototype's `mulberry32`.
/// Used to lay out the constellation with stable, reproducible jitter (SPEC §7 layout
/// algorithms). Pure integer bit-twiddling (UInt32 overflow arithmetic + a manual
/// bits→Double normalization), so output is identical across runs/machines and never
/// pulls in platform randomness. Keep this in the domain — layout is policy, not UI.
struct SeededGenerator {
    private var state: UInt32

    init(seed: UInt32) { state = seed }

    /// Next value in `[0, 1)`. Matches the reference JS bit-for-bit (see tests).
    mutating func next() -> Double {
        state = state &+ 0x6D2B79F5
        var x = state
        x = (x ^ (x >> 15)) &* (x | 1)
        x = x ^ (x &+ ((x ^ (x >> 7)) &* (x | 61)))
        x = x ^ (x >> 14)
        return Double(x) / 4294967296.0   // 2^32
    }
}
