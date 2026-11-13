@preconcurrency import AVFoundation
import EditorCore

/// Follows something in the video for a title or sticker, on this Mac (`PatchTracker`: the
/// patch of picture under it, found again frame after frame). It watches the Short as drawn,
/// without titles, stickers or captions, so it follows what the viewer sees wherever the clip
/// is framed, zoomed or moved.
public enum SubjectTracker {
    public enum TrackError: LocalizedError {
        case nothingToFollow

        public var errorDescription: String? {
            "Nothing could be followed there. Put the title or sticker on something that stands out (a face, a product), at its first moment, and try again."
        }
    }

    /// Pictures looked at per second.
    static let rate = 15.0
    /// The size the pictures are looked at (a quarter of the canvas).
    static let width = 270, height = 480
    /// The patch followed: a square this fraction of the canvas width across.
    static let patchWidth = 0.18
    /// How far it can move between two pictures, as a fraction of the canvas width.
    static let reach = 0.1

    /// The path of what is at `point` (fractions of the canvas) at the start of `range`, through
    /// `range` of `project`'s timeline. Where it is lost, the path stops (the item then stays
    /// where it was last).
    public static func track(project: Project, at point: (x: Double, y: Double), during range: CMTimeRange,
                             progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> [TrackPoint] {
        var plain = project
        plain.titles = []
        plain.captions.isVisible = false
        let built = try await CompositionBuilder.build(plain)
        let generator = AVAssetImageGenerator(asset: built.composition)
        generator.videoComposition = built.videoComposition
        generator.maximumSize = CGSize(width: width, height: height)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        let count = max(Int(range.duration.seconds * rate), 1)
        let times = (0...count).map { range.start + CMTime(seconds: Double($0) / rate, preferredTimescale: 600) }.filter { $0 < range.end }
        guard let first = try? await gray(generator.image(at: range.start).image) else { throw TrackError.nothingToFollow }
        var tracker = PatchTracker(frame: first, x: point.x * Double(first.width), y: point.y * Double(first.height),
                                   radius: Int(patchWidth * Double(first.width) / 2), reach: Int(reach * Double(first.width)))
        var points: [TrackPoint] = [TrackPoint(offset: .zero, x: point.x, y: point.y)]
        for (index, time) in times.enumerated() where index > 0 {
            try Task.checkCancellation()
            guard let frame = try? await gray(generator.image(at: time).image) else { break }
            guard tracker.next(frame) != nil else { break }
            points.append(TrackPoint(offset: time - range.start, x: tracker.x / Double(frame.width), y: tracker.y / Double(frame.height)))
            progress(Double(index) / Double(times.count))
        }
        progress(1)
        guard points.count > 1 else { throw TrackError.nothingToFollow }
        return points
    }

    /// The picture in shades of grey.
    static func gray(_ image: CGImage) -> GrayFrame? {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return GrayFrame(width: width, height: height, pixels: bytes.map(Float.init))
    }
}
