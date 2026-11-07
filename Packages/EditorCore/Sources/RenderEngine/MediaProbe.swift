import AVFoundation
import EditorCore

/// Reads what the editor needs to know about a file before it can be used.
public enum MediaProbe {
    public enum ProbeError: LocalizedError {
        case noVideo
        case empty

        public var errorDescription: String? {
            switch self {
            case .noVideo: "The file has no video in it."
            case .empty: "The video is empty."
            }
        }
    }

    public static func probe(_ url: URL) async throws -> MediaAsset {
        let asset = AVURLAsset(url: url)
        guard let video = try await asset.loadTracks(withMediaType: .video).first else {
            throw ProbeError.noVideo
        }
        let (timeRange, naturalSize, transform) = try await video.load(.timeRange, .naturalSize, .preferredTransform)
        guard timeRange.duration > .zero else { throw ProbeError.empty }
        let hasAudio = try await !asset.loadTracks(withMediaType: .audio).isEmpty
        let oriented = CGRect(origin: .zero, size: naturalSize).applying(transform)
        return MediaAsset(
            url: url,
            name: url.deletingPathExtension().lastPathComponent,
            // The video track's own length, not the file's: audio can run a few frames longer.
            duration: timeRange.duration,
            displaySize: CGSize(width: abs(oriented.width), height: abs(oriented.height)),
            hasAudio: hasAudio
        )
    }

    /// A small upright still from early in the video, for lists and the timeline.
    public static func thumbnail(for url: URL, maxSize: CGSize = CGSize(width: 320, height: 320)) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maxSize
        // Half a second in avoids the black first frame many recordings start with.
        return try await generator.image(at: CMTime(value: 1, timescale: 2)).image
    }
}
