@preconcurrency import AVFoundation
import EditorCore

/// The picture a Short shows on the home window: one frame of the finished Short, with its
/// framing, B-roll, titles and captions, as the compositor draws it.
public enum ProjectPoster {
    /// When the poster is taken: a second in (past fades and the black first frame), or the
    /// middle of a shorter Short.
    public static func time(in project: Project) -> CMTime {
        let duration = project.duration
        let second = CMTime(value: 1, timescale: 1)
        return duration > second + second ? second : CMTime(seconds: duration.seconds / 2, preferredTimescale: 600)
    }

    public static func image(of project: Project, maxSize: CGSize = CGSize(width: 360, height: 640)) async throws -> CGImage {
        let built = try await CompositionBuilder.build(project)
        let generator = AVAssetImageGenerator(asset: built.composition)
        generator.videoComposition = built.videoComposition
        generator.maximumSize = maxSize
        return try await generator.image(at: time(in: project)).image
    }
}
