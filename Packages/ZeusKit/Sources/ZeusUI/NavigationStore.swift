import Foundation
import Observation
import ZeusDomain

/// The constellation's UDF store: the single source of truth for navigation state. All state
/// changes flow through the pure `NavigationReducer`; the store's only added responsibility is
/// owning *when* the timed phase transitions fire (SPEC §7: switch to `enter` at 430ms, to
/// `idle` at 480ms). The clock is injected so that timing is deterministic in tests.
///
/// A user action that opens a transition leaves `phase == .leave`; the store then schedules the
/// `phaseAdvance`/`phaseSettle` hops on the clock. Under Reduce Motion the reducer settles to
/// `.idle` immediately, so nothing is scheduled.
@MainActor
@Observable
public final class NavigationStore {
    public private(set) var state: NavigationState

    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private var transitionTask: Task<Void, Never>?

    /// SPEC §7 timings: `enter` at 430ms, `idle` at 480ms (so the second hop is 50ms after the first).
    @ObservationIgnored private let advanceDelay: Duration = .milliseconds(430)
    @ObservationIgnored private let settleDelay: Duration = .milliseconds(50)

    public init(state: NavigationState = .initial, clock: any Clock<Duration> = ContinuousClock()) {
        self.state = state
        self.clock = clock
    }

    /// Apply an action through the reducer, then schedule the timed phase hops if it opened a
    /// transition. Phase actions (`phaseAdvance`/`phaseSettle`) re-enter here but never re-schedule.
    public func dispatch(_ action: NavigationAction) {
        let before = state
        state = NavigationReducer.reduce(state, action)
        if state.phase == .leave && before.phase != .leave {
            scheduleTransition()
        }
    }

    /// Reduce Motion is presentation state the View pushes from its `@Environment`; the reducer
    /// reads it to decide whether to animate, so keep it current before dispatching a dive/back.
    public func setReduceMotion(_ value: Bool) {
        state.reduceMotion = value
    }

    /// Await the in-flight phase transition to finish (no-op if none). A testability seam: it lets
    /// tests drive the timed effect to completion deterministically rather than polling the clock.
    public func waitForTransition() async {
        await transitionTask?.value
    }

    private func scheduleTransition() {
        transitionTask?.cancel()
        let advanceDelay = advanceDelay, settleDelay = settleDelay
        transitionTask = Task { [weak self, clock] in
            try? await clock.sleep(for: advanceDelay)
            guard let self, !Task.isCancelled else { return }
            self.dispatch(.phaseAdvance)
            try? await clock.sleep(for: settleDelay)
            guard !Task.isCancelled else { return }
            self.dispatch(.phaseSettle)
        }
    }
}
