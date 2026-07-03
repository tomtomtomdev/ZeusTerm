import Testing
@testable import ZeusDomain

/// Keyboard focus for the constellation star map (SPEC §7: "the star map is not mouse-only").
/// `StageFocus` is pure directional navigation over nodes carrying an `id` + a `StagePoint` in the
/// shared 1040×540 stage space — the same coordinates every level already lays out — so hub stars,
/// orbit satellites, and commit nodes all traverse through one tested policy. Stage coords put the
/// origin top-left with y growing downward (matching layout), so "up" means a smaller y.
struct StageFocusTests {
    // A 2×2 grid: A top-left, B top-right, C bottom-left, D bottom-right.
    private let grid = [
        FocusNode(id: "A", point: StagePoint(x: 100, y: 100)),
        FocusNode(id: "B", point: StagePoint(x: 300, y: 100)),
        FocusNode(id: "C", point: StagePoint(x: 100, y: 300)),
        FocusNode(id: "D", point: StagePoint(x: 300, y: 300)),
    ]

    // MARK: Directional movement

    @Test func rightPicksTheNodeToTheRight() {
        #expect(StageFocus.next(from: "A", direction: .right, in: grid) == "B")
    }

    @Test func downPicksTheNodeBelow() {
        #expect(StageFocus.next(from: "A", direction: .down, in: grid) == "C")
    }

    @Test func leftPicksTheNodeToTheLeft() {
        #expect(StageFocus.next(from: "B", direction: .left, in: grid) == "A")
    }

    @Test func upPicksTheNodeAbove() {
        #expect(StageFocus.next(from: "C", direction: .up, in: grid) == "A")
    }

    @Test func noNodeInTheDirectionIsANoOp() {
        // Nothing above A → nil signals "stay put" so the view keeps the current focus.
        #expect(StageFocus.next(from: "A", direction: .up, in: grid) == nil)
    }

    @Test func prefersTheAxis_alignedNeighborOverACloserDiagonalOne() {
        // B is aligned (dy 0); E is nearer in raw distance but off-axis — right should land on B.
        let nodes = grid + [FocusNode(id: "E", point: StagePoint(x: 260, y: 210))]
        #expect(StageFocus.next(from: "A", direction: .right, in: nodes) == "B")
    }

    @Test func movingWithNoCurrentFocusSeedsTheEntryNode() {
        // A stray arrow before focus is seeded enters at the topmost-leftmost node.
        #expect(StageFocus.next(from: nil, direction: .down, in: grid) == "A")
    }

    // MARK: Initial focus

    @Test func initialFocusIsTheTopmostLeftmostNode() {
        #expect(StageFocus.initialFocus(in: grid) == "A")
    }

    @Test func initialFocusHonorsAnExistingPreferredNode() {
        // The tree level seeds on HEAD; pass it as `preferred` and it wins when present.
        #expect(StageFocus.initialFocus(in: grid, preferred: "D") == "D")
    }

    @Test func initialFocusFallsBackWhenThePreferredNodeIsAbsent() {
        #expect(StageFocus.initialFocus(in: grid, preferred: "ghost") == "A")
    }

    @Test func initialFocusOfAnEmptyMapIsNil() {
        #expect(StageFocus.initialFocus(in: []) == nil)
    }
}
