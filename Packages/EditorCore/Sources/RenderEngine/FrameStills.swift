@preconcurrency import AVFoundation
import EditorCore
import Synchronization

/// Single pictures of videos, for freeze frames and for clips held on their first or last picture
/// during a transition. Read the same way the player reads frames, so a freeze frame looks exactly
/// like the moving picture it stops, and kept while they are used.
public nonisolated enum FrameStills {
    public struct Still: @unchecked Sendable {
        let buffer: CVPixelBuffer
        /// The size and orientation as stored in the file, like a track's.
        let naturalSize: CGSize
        let preferredTransform: CGAffineTransform
    }

    private static let cache = Mutex<[String: Still]>([:])
    /// A 4K frame is over 30 MB, so only a few are kept.
    private static let limit = 16

    /// The picture showing at `time` in the video at `url`, or nil when it can't be read.
    @concurrent
    public static func still(of url: URL, at time: CMTime) async -> Still? {
        let key = "\(url.path)|\(time.value)/\(time.timescale)"
        if let cached = cache.withLock({ $0[key] }) { return cached }
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let (size, transform, range) = try? await track.load(.naturalSize, .preferredTransform, .timeRange),
              let reader = try? AVAssetReader(asset: asset)
        else { return nil }
        // Start a little early and keep the last picture that begins at or before the time: that
        // is the one on screen then.
        let wanted = time.clamped(range.start, range.end)
        let start = max(range.start, wanted - CMTime(value: 1, timescale: 2))
        reader.timeRange = CMTimeRange(start: start, end: range.end)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        var found: CVPixelBuffer?
        let slack = CMTime(value: 1, timescale: 1000)
        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let shown = CMSampleBufferGetPresentationTimeStamp(sample)
            if found == nil || shown <= wanted + slack { found = buffer }
            if shown >= wanted - slack { break }
        }
        reader.cancelReading()
        guard let found else { return nil }
        let still = Still(buffer: found, naturalSize: size, preferredTransform: transform)
        cache.withLock { cache in
            if cache.count >= limit { cache.removeAll() }
            cache[key] = still
        }
        return still
    }

    /// Forgets the pictures of a file, e.g. after it was relinked.
    public static func forget(_ url: URL) {
        cache.withLock { cache in
            for key in cache.keys where key.hasPrefix(url.path + "|") { cache[key] = nil }
        }
    }
}
