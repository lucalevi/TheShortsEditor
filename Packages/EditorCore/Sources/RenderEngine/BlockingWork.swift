import Dispatch

/// Work that blocks its thread (an `AVAssetReader` decoding frames with `copyNextSampleBuffer`),
/// run on threads of its own instead of Swift's shared ones.
///
/// Swift's concurrency runs every task on a few shared threads (one per core). Work that blocks
/// one of them holds it until it is done; when several builds blocked at once (quick edits on a
/// Short with a transition held on a still), every shared thread was taken and nothing, not even
/// the work they waited on, could go on: the app hung (found by `CancellationStressTests`,
/// 2026-11-16). Dispatch makes more threads when these block.
nonisolated enum BlockingWork {
    private static let queue = DispatchQueue(label: "com.lucalevi.shortseditor.blocking", qos: .userInitiated, attributes: .concurrent)

    /// Runs `body` on a thread of its own (on `queue`, if given: e.g. a serial one, so such work
    /// runs one at a time) and waits for its result without blocking the caller.
    static func run<T: Sendable>(on queue: DispatchQueue? = nil, _ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            (queue ?? Self.queue).async { continuation.resume(returning: body()) }
        }
    }
}

/// Carries a value that isn't `Sendable` (an AVFoundation object) to another thread, when only
/// one thread uses it at a time.
nonisolated struct Unchecked<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
