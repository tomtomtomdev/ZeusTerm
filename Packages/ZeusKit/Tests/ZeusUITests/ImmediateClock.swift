import Foundation

/// A `Clock` test double whose sleeps return immediately — it drives the store's timed phase
/// transition to completion with no real delay, so tests can deterministically `await` the
/// in-flight transition (`NavigationStore.waitForTransition()`) instead of racing `Task.yield()`.
/// Zero dependencies, mirroring `ContinuousClock`'s shape (the package's offline-buildable ethos).
///
/// We deliberately don't unit-test the *literal* 430/480ms timings — those are brittle to assert
/// and are validated by feel in the `S2ZoomSpike` harness / `/verify`. The store's testable
/// responsibility is that a dive/back schedules an effect that settles to `.idle` on the chosen view.
struct ImmediateClock: Clock {
    struct Instant: InstantProtocol {
        var offset: Duration
        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    var now: Instant { Instant(offset: .zero) }
    var minimumResolution: Duration { .zero }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try Task.checkCancellation()   // return immediately, but still honor cancellation
    }
}
