import Dispatch
import Synchronization

/// Work that blocks its thread (an `AVAssetReader` decoding frames with `copyNextSampleBuffer`),
/// run on threads of its own instead of Swift's shared ones.
///
/// Swift's concurrency runs every task on a few shared threads (one per core). Work that blocks
/// one of them holds it until it is done; when several builds blocked at once (quick edits on a
/// Short with a transition held on a still), every shared thread was taken and nothing, not even
/// the work they waited on, could go on: the app hung (found by `CancellationStressTests`,
/// 2026-11-16). Dispatch makes more threads when these block.
package enum BlockingWork {
    private static let queue = DispatchQueue(label: "com.lucalevi.shortseditor.blocking", qos: .userInitiated, attributes: .concurrent)

    /// Runs `body` on a thread of its own (on `queue`, if given: e.g. a serial one, so such work
    /// runs one at a time) and waits for its result without blocking the caller.
    package static func run<T: Sendable>(on queue: DispatchQueue? = nil, _ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            (queue ?? Self.queue).async { continuation.resume(returning: body()) }
        }
    }

    /// Like `run`, for work that can fail or be stopped: `body` calls `stop.check()` now and then,
    /// which throws `CancellationError` once the calling task is cancelled (`Task.checkCancellation`
    /// can't see that task from another thread).
    package static func run<T: Sendable>(on queue: DispatchQueue? = nil, _ body: @escaping @Sendable (Stop) throws -> T) async throws -> T {
        let stop = Stop()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                (queue ?? Self.queue).async { continuation.resume(with: Result { try body(stop) }) }
            }
        } onCancel: {
            stop.cancel()
        }
    }

    /// Set when the task that started some blocking work is cancelled.
    package final class Stop: Sendable {
        private let cancelled = Atomic<Bool>(false)

        package var isCancelled: Bool { cancelled.load(ordering: .relaxed) }

        package func cancel() { cancelled.store(true, ordering: .relaxed) }

        /// Throws `CancellationError` once the work should stop.
        package func check() throws {
            if isCancelled { throw CancellationError() }
        }
    }
}

/// Carries a value that isn't `Sendable` (an AVFoundation object) to another thread, when only
/// one thread uses it at a time.
package struct Unchecked<Value>: @unchecked Sendable {
    package let value: Value
    package init(_ value: Value) { self.value = value }
}
