import AVFoundation
import EditorCore

/// What AVFoundation needs to play (and later export) a project.
public struct PlayableComposition {
    public let composition: AVComposition
    public let videoComposition: AVVideoComposition

    @MainActor
    public func makePlayerItem() -> AVPlayerItem {
        let item = AVPlayerItem(asset: composition)
        item.videoComposition = videoComposition
        return item
    }
}

/// Turns a `Project` into a `PlayableComposition`. It is rebuilt from scratch after every edit;
/// the project, not the composition, is the source of truth.
@MainActor
public enum CompositionBuilder {
    public enum BuildError: LocalizedError {
        case emptyTimeline
        case missingAsset(String)
        case unreadable(String)

        public var errorDescription: String? {
            switch self {
            case .emptyTimeline: "The timeline is empty."
            case .missingAsset(let name): "The media for “\(name)” is missing."
            case .unreadable(let name): "“\(name)” can't be read."
            }
        }
    }

    public static func build(_ project: Project) async throws -> PlayableComposition {
        guard !project.timeline.clips.isEmpty else { throw BuildError.emptyTimeline }

        let composition = AVMutableComposition()
        guard
            let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
            let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw BuildError.unreadable("composition") }

        var sources: [MediaAsset.ID: AVURLAsset] = [:]
        var instructions: [any AVVideoCompositionInstructionProtocol] = []
        var cursor = CMTime.zero
        let captions = CaptionTrack(project: project)
        let titles = TitleTrack(project: project)

        for clip in project.timeline.clips {
            guard let media = project.asset(id: clip.assetID) else {
                throw BuildError.missingAsset(clip.assetID.uuidString)
            }
            let source = sources[media.id] ?? AVURLAsset(url: media.url)
            sources[media.id] = source

            guard let sourceVideo = try await source.loadTracks(withMediaType: .video).first else {
                throw BuildError.unreadable(media.name)
            }
            try videoTrack.insertTimeRange(clip.sourceRange, of: sourceVideo, at: cursor)

            if let sourceAudio = try await source.loadTracks(withMediaType: .audio).first {
                // Audio may be a little shorter than the video; insert only what exists and pad
                // so the next clip's sound still starts exactly with its picture.
                let available = try await sourceAudio.load(.timeRange)
                let range = clip.sourceRange.intersection(available)
                if range.duration > .zero {
                    let insertAt = cursor + (range.start - clip.sourceStart)
                    padToTime(audioTrack, insertAt)
                    try audioTrack.insertTimeRange(range, of: sourceAudio, at: insertAt)
                }
            }

            let (naturalSize, preferredTransform) = try await sourceVideo.load(.naturalSize, .preferredTransform)
            instructions.append(ShortsInstruction(
                timeRange: CMTimeRange(start: cursor, duration: clip.duration),
                trackID: videoTrack.trackID,
                transform: clip.framing.transform(naturalSize: naturalSize, preferredTransform: preferredTransform),
                captions: captions,
                titles: titles
            ))

            cursor = cursor + clip.duration
        }

        if audioTrack.segments.isEmpty {
            composition.removeTrack(audioTrack)
        }

        let videoComposition = AVVideoComposition(configuration: .init(
            customVideoCompositorClass: ShortsCompositor.self,
            frameDuration: .oneFrame,
            instructions: instructions,
            renderSize: Project.canvasSize
        ))
        return PlayableComposition(composition: composition, videoComposition: videoComposition)
    }

    private static func padToTime(_ track: AVMutableCompositionTrack, _ time: CMTime) {
        let end = track.segments.isEmpty ? .zero : track.timeRange.end
        if end < time {
            track.insertEmptyTimeRange(CMTimeRange(start: end, end: time))
        }
    }
}
