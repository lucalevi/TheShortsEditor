@preconcurrency import AVFoundation
import EditorCore
import Vision

/// Finds where the subject is in a clip's picture, for following it in a vertical Short: the
/// biggest face when there is one, otherwise what draws the eye (Vision's attention saliency).
public enum Reframer {
    /// How often a frame is looked at.
    static let interval = 0.25

    /// The subject's middle across the picture (0 left … 1 right) through `clip`'s part of its
    /// source. Reports progress 0…1.
    public static func samples(for clip: Clip, media: MediaAsset, progress: @escaping (Double) -> Void = { _ in }) async throws -> [Reframe.Sample] {
        if media.isImage {
            guard let image = StillImages.image(at: media.url) else { return [] }
            return [Reframe.Sample(time: clip.sourceStart, x: try subjectX(in: image))]
        }
        let range = clip.sourceRange
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: media.url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        let tolerance = CMTime(seconds: interval / 2, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        var times: [CMTime] = []
        var t = range.start
        while t < range.end {
            times.append(t)
            t = t + CMTime(seconds: interval, preferredTimescale: 600)
        }
        var samples: [Reframe.Sample] = []
        var done = 0
        for await result in generator.images(for: times) {
            try Task.checkCancellation()
            done += 1
            progress(Double(done) / Double(max(times.count, 1)))
            guard let image = try? result.image else { continue }
            samples.append(Reframe.Sample(time: result.requestedTime, x: try subjectX(in: image)))
        }
        return samples
    }

    /// Where the subject is across `image`: 0 left … 1 right, 0.5 when nothing stands out.
    nonisolated static func subjectX(in image: CGImage) throws -> Double {
        let handler = VNImageRequestHandler(cgImage: image)
        let faces = VNDetectFaceRectanglesRequest()
        let attention = VNGenerateAttentionBasedSaliencyImageRequest()
        try handler.perform([faces, attention])
        if let face = faces.results?.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }) {
            return Double(face.boundingBox.midX)
        }
        let objects = attention.results?.first?.salientObjects ?? []
        guard let biggest = objects.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }) else { return 0.5 }
        return Double(biggest.boundingBox.midX)
    }
}
