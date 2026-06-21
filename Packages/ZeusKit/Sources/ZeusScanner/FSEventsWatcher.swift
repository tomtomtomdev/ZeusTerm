import CoreServices
import Foundation
import ZeusDomain

/// FSEvents-backed `FileSystemWatching` adapter (P3-D.3b). Wraps the FSEvents C API into an
/// `AsyncStream<String>` of changed paths so the store can keep the Hub live. FSEvents coalesces
/// rapid changes at the OS latency window and delivers a batch of paths per callback; this
/// flattens the batch into the stream. Cancelling the task iterating the stream tears the
/// FSEvents stream down (via the continuation's termination handler).
///
/// The decision logic lives outside this adapter — `ChangeRelevance` (D.3a) drops build/dependency
/// noise, the store debounces (D.3c) — so this stays thin glue, proven by a bounded integration
/// test plus `/verify` in the running app.
public struct FSEventsWatcher: FileSystemWatching {
    private let latency: TimeInterval

    /// `latency` is the FSEvents coalescing window: the OS waits this long after the first event
    /// before delivering the batch, trading immediacy for fewer wake-ups. The store debounces on
    /// top, so a small default is fine.
    public init(latency: TimeInterval = 0.3) {
        self.latency = latency
    }

    public func changes(under roots: [URL]) -> AsyncStream<String> {
        AsyncStream { continuation in
            // Nothing to watch: finish straight away so the consumer's `for await` exits cleanly
            // rather than waiting on a stream that can never emit.
            guard !roots.isEmpty else {
                continuation.finish()
                return
            }
            let session = FSEventStreamSession(continuation: continuation)
            // Set teardown before starting so an immediate cancellation can't race a live stream.
            continuation.onTermination = { _ in session.stop() }
            session.start(paths: roots.map(\.path), latency: latency)
        }
    }
}

/// Owns one FSEvents stream's lifecycle and bridges its C callback to an `AsyncStream`
/// continuation. `@unchecked Sendable`: the only mutable state (`stream`) is guarded by `lock`,
/// and the continuation is itself `Sendable` and safe to `yield` to after `finish` (a no-op).
private final class FSEventStreamSession: @unchecked Sendable {
    private let continuation: AsyncStream<String>.Continuation
    private let lock = NSLock()
    private var stream: FSEventStreamRef?
    // A strong self-retain handed to the C stream via `context.info`, balanced in `stop()`. It
    // guarantees the session outlives every callback the queue might still run during teardown —
    // without it `self` is retained only by the continuation's termination handler, which can
    // release before an in-flight callback dereferences the (unretained) `info` pointer.
    private var retainedSelf: Unmanaged<FSEventStreamSession>?
    // A dedicated serial queue for FSEvents callbacks (modern alternative to a run loop).
    private let queue = DispatchQueue(label: "co.zeus.fsevents")

    init(continuation: AsyncStream<String>.Continuation) {
        self.continuation = continuation
    }

    func start(paths: [String], latency: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        guard stream == nil else { return }

        let token = Unmanaged.passRetained(self)
        retainedSelf = token
        var context = FSEventStreamContext(
            version: 0,
            info: token.toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        // UseCFTypes → callback receives a CFArray of CFString (bridged to [String]); FileEvents →
        // file-level paths (so relevance filtering sees the real file); NoDefer → deliver the first
        // batch after `latency` from the first event rather than deferring a full window.
        let flags = UInt32(
            kFSEventStreamCreateFlagUseCFTypes
            | kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagNoDefer
        )
        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            eventCallback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            // No stream to tear down later, so balance the retain here.
            retainedSelf?.release()
            retainedSelf = nil
            continuation.finish()
            return
        }
        stream = created
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)   // no further callbacks after this returns
        FSEventStreamRelease(stream)
        self.stream = nil
        continuation.finish()
        // Drop the strong self-retain last: every possible callback is now done.
        retainedSelf?.release()
        retainedSelf = nil
    }
}

/// C callback for FSEvents. It can't capture context, so the session is threaded through
/// `clientCallBackInfo` (`context.info`) and recovered here to yield onto its continuation.
private let eventCallback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
    guard let info else { return }
    let session = Unmanaged<FSEventStreamSession>.fromOpaque(info).takeUnretainedValue()
    // UseCFTypes was set, so eventPaths is a CFArray of CFString.
    let paths = unsafeBitCast(eventPaths, to: NSArray.self)
    for case let path as String in paths {
        session.yield(path)
    }
}

private extension FSEventStreamSession {
    /// Forwards a changed path to the continuation. Kept off the public surface; yielding after
    /// the stream finished is safe (the continuation returns `.terminated` and drops it).
    func yield(_ path: String) {
        continuation.yield(path)
    }
}
