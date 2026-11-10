import AVFoundation
import EditorCore
import ImageIO
import UniformTypeIdentifiers

/// Reads what the editor needs to know about a file before it can be used.
public enum MediaProbe {
    public enum ProbeError: LocalizedError {
        case noVideo
        case empty
        case unreadablePicture

        public var errorDescription: String? {
            switch self {
            case .noVideo: "The file has no video or sound in it."
            case .empty: "The file is empty."
            case .unreadablePicture: "The picture can't be read."
            }
        }
    }

    /// Whether `url` names a still picture (photo, screenshot) rather than a video or sound.
    public static func isPicture(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image) && !type.conforms(to: .movie)
    }

    /// Reads a video file, a picture, or a sound file (music, which comes back with `hasVideo` false).
    public static func probe(_ url: URL) async throws -> MediaAsset {
        if isPicture(url) {
            guard let size = StillImages.size(at: url) else { throw ProbeError.unreadablePicture }
            return .image(url: url, size: size)
        }
        let asset = AVURLAsset(url: url)
        guard let video = try await asset.loadTracks(withMediaType: .video).first else {
            guard let sound = try await asset.loadTracks(withMediaType: .audio).first else { throw ProbeError.noVideo }
            let range = try await sound.load(.timeRange)
            guard range.duration > .zero else { throw ProbeError.empty }
            return MediaAsset(
                url: url, name: url.deletingPathExtension().lastPathComponent,
                duration: range.end, displaySize: .zero, hasAudio: true, hasVideo: false
            )
        }
        let (timeRange, naturalSize, transform) = try await video.load(.timeRange, .naturalSize, .preferredTransform)
        let frameRate = try? await video.load(.nominalFrameRate)
        guard timeRange.duration > .zero else { throw ProbeError.empty }
        let hasAudio = try await !asset.loadTracks(withMediaType: .audio).isEmpty
        let oriented = CGRect(origin: .zero, size: naturalSize).applying(transform)
        return MediaAsset(
            url: url,
            name: url.deletingPathExtension().lastPathComponent,
            // The video track's own length, not the file's: audio can run a few frames longer.
            duration: timeRange.duration,
            displaySize: CGSize(width: abs(oriented.width), height: abs(oriented.height)),
            hasAudio: hasAudio,
            frameRate: frameRate.flatMap { $0 > 0 ? Double($0) : nil }
        )
    }

    /// A small upright still of a picture, or from early in a video, for lists and the timeline.
    public static func thumbnail(for media: MediaAsset, maxSize: CGSize = CGSize(width: 320, height: 320)) async throws -> CGImage {
        if media.isImage {
            guard let image = pictureThumbnail(media.url, maxPixels: Int(max(maxSize.width, maxSize.height))) else { throw ProbeError.unreadablePicture }
            return image
        }
        return try await thumbnail(for: media.url, maxSize: maxSize)
    }

    /// A small upright still from early in the video, for lists and the timeline.
    public static func thumbnail(for url: URL, maxSize: CGSize = CGSize(width: 320, height: 320)) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maxSize
        // Half a second in avoids the black first frame many recordings start with.
        return try await generator.image(at: CMTime(value: 1, timescale: 2)).image
    }

    /// An upright frame of a video at `time`, near enough (a twentieth of a second) to be quick,
    /// for skimming through a file.
    public static func frame(of url: URL, at time: CMTime, maxSize: CGSize = CGSize(width: 720, height: 1280)) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maxSize
        let tolerance = CMTime(value: 1, timescale: 20)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        return try await generator.image(at: time).image
    }
}

/// Small stills along a video, for drawing a strip of pictures on its clips.
public nonisolated struct Filmstrip: @unchecked Sendable {
    /// Source time between two stills (zero for a picture, which has a single still).
    public let interval: CMTime
    public let images: [CGImage]

    /// The still nearest `time` in the source.
    public func image(at time: CMTime) -> CGImage? {
        guard !images.isEmpty else { return nil }
        guard interval > .zero else { return images[0] }
        let index = Int((time.seconds / interval.seconds).rounded(.down))
        return images[min(max(index, 0), images.count - 1)]
    }
}

public extension MediaProbe {
    /// The most stills made for one file: a still a second up to this many, then further apart.
    static let filmstripLimit = 120

    /// Stills along `media` about `height` pixels high: one per second (fewer for long videos),
    /// or the picture itself.
    static func filmstrip(for media: MediaAsset, height: CGFloat = 120) async throws -> Filmstrip {
        if media.isImage {
            guard let image = pictureThumbnail(media.url, maxPixels: Int(height * 2)) else { throw ProbeError.unreadablePicture }
            return Filmstrip(interval: .zero, images: [image])
        }
        let seconds = max(media.duration.seconds, 0.1)
        let interval = CMTime(seconds: max(1, seconds / Double(filmstripLimit)), preferredTimescale: 600)
        let count = max(1, Int((seconds / interval.seconds).rounded(.up)))
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: media.url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: height * 2, height: height)
        generator.requestedTimeToleranceBefore = CMTimeMultiplyByRatio(interval, multiplier: 1, divisor: 2)
        generator.requestedTimeToleranceAfter = CMTimeMultiplyByRatio(interval, multiplier: 1, divisor: 2)
        // Each still shows the middle of its stretch.
        let times = (0..<count).map { CMTimeAdd(CMTimeMultiply(interval, multiplier: Int32($0)), CMTimeMultiplyByRatio(interval, multiplier: 1, divisor: 2)) }
            .map { min($0, media.duration) }
        var images: [CGImage] = []
        var last: CGImage?
        for await result in generator.images(for: times) {
            // A still that can't be made repeats the one before, so the strip stays in step.
            if let image = try? result.image { last = image }
            if let last { images.append(last) }
        }
        return Filmstrip(interval: interval, images: images)
    }

    /// A picture file made small, the right way up.
    private static func pictureThumbnail(_ url: URL, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ] as CFDictionary)
    }
}
