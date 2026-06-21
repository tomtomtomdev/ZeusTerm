import Foundation
import Testing
@testable import ZeusScanner

/// P3-D.3b — the FSEvents-backed `FileSystemWatching` adapter. FSEvents is a system streaming
/// API driven by OS timing (the same class as the PTY in S1), so the deterministic decision
/// logic lives elsewhere — relevance filtering in `ChangeRelevance` (D.3a), debounce in the
/// store with an injected clock (D.3c). What's proven here: the adapter actually emits a path
/// when the watched tree changes, and degrades cleanly on the empty-roots edge.
///
/// The change test is a real integration test (like the GitCLIService / ProjectScanner fixtures)
/// but hard-bounded by `withTimeout` so a missed event fails fast instead of hanging the suite.
///
/// Test List:
///  [x] no roots                          → stream finishes immediately, emits nothing
///  [x] a file written under a watched root → the changed path is emitted
struct FSEventsWatcherTests {

    @Test func changesUnderNoRootsFinishImmediately() async {
        let watcher = FSEventsWatcher()

        var emitted: [String] = []
        for await path in watcher.changes(under: []) { emitted.append(path) }

        #expect(emitted.isEmpty)
    }

    @Test func emitsAChangedPathWhenAFileIsWrittenUnderAWatchedRoot() async throws {
        // A uniquely-named root so the emitted path is unambiguous regardless of the /private
        // symlink FSEvents canonicalises temp dirs through (it reports /private/var/… while the
        // URL says /var/…), and regardless of file- vs directory-level event granularity.
        let unique = "zeus-fsevents-\(UUID().uuidString)"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(unique, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let watcher = FSEventsWatcher(latency: 0.05)
        let stream = watcher.changes(under: [root])

        let observer = Task { () -> Bool in
            for await path in stream where path.contains(unique) { return true }
            return false
        }
        // Poke the dir until observed or the deadline — covers the small window before the
        // FSEvents stream is armed (events predating it are not delivered with sinceNow).
        let writer = Task {
            for i in 0..<60 where !Task.isCancelled {
                try? Data("\(i)".utf8).write(to: root.appendingPathComponent("probe.txt"))
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        defer { writer.cancel(); observer.cancel() }

        let observed = try await withTimeout(seconds: 10) { await observer.value }
        #expect(observed)
    }
}

private struct TimeoutError: Error {}

/// Runs `operation`, failing with `TimeoutError` after `seconds` so a watcher that never emits
/// can't hang the suite. Cancelling the group cancels the AsyncStream iteration (which finishes
/// on cancellation), so nothing is left running.
private func withTimeout<T: Sendable>(
    seconds: Double,
    _ operation: @escaping @Sendable () async -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw TimeoutError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
