import AVFoundation
import EditorCore

/// What AVFoundation needs to play (and later export) a project.
public struct PlayableComposition {
    public let composition: AVComposition
    public let videoComposition: AVVideoComposition
    /// Clip volumes and the music's volume curve.
    public let audioMix: AVAudioMix
    /// The music's volume over the timeline (before any export gain), for drawing it.
    public let musicEnvelope: [VolumePoint]

    @MainActor
    public func makePlayerItem() -> AVPlayerItem {
        let item = AVPlayerItem(asset: composition)
        item.videoComposition = videoComposition
        item.audioMix = audioMix
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

    /// `gain` scales all sound, for bringing the export to YouTube's loudness.
    public static func build(_ project: Project, gain: Double = 1) async throws -> PlayableComposition {
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
        let clipSound = AVMutableAudioMixInputParameters(track: audioTrack)

        for clip in project.timeline.clips {
            guard let media = project.asset(id: clip.assetID), media.hasVideo else {
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

            clipSound.setVolume(Float(clip.effectiveVolume * gain), at: cursor)

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

        var mixInputs: [AVAudioMixInputParameters] = []
        if audioTrack.segments.isEmpty {
            composition.removeTrack(audioTrack)
        } else {
            mixInputs.append(clipSound)
        }

        // The background song, on its own track, with its volume curve.
        var envelope: [VolumePoint] = []
        if let track = project.music, let range = project.musicRange, let song = project.asset(id: track.assetID),
           // Kept in `sources`: a track is only usable while its asset is alive.
           let songAudio = try await {
               let asset = sources[song.id] ?? AVURLAsset(url: song.url)
               sources[song.id] = asset
               return try await asset.loadTracks(withMediaType: .audio).first
           }(),
           let musicTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let available = try await songAudio.load(.timeRange)
            let source = CMTimeRange(start: track.sourceStart, duration: range.duration).intersection(available)
            if source.duration > .zero {
                try musicTrack.insertTimeRange(source, of: songAudio, at: source.start - track.sourceStart)
                envelope = AudioMix.musicEnvelope(for: project, speech: track.lowersUnderSpeech ? await speech(in: project) : [])
                let parameters = AVMutableAudioMixInputParameters(track: musicTrack)
                for (a, b) in zip(envelope, envelope.dropFirst()) where b.time > a.time {
                    parameters.setVolumeRamp(fromStartVolume: Float(a.volume * gain), toEndVolume: Float(b.volume * gain),
                                             timeRange: CMTimeRange(start: a.time, end: b.time))
                }
                mixInputs.append(parameters)
            } else {
                composition.removeTrack(musicTrack)
            }
        }
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = mixInputs

        let videoComposition = AVVideoComposition(configuration: .init(
            customVideoCompositorClass: ShortsCompositor.self,
            frameDuration: .oneFrame,
            instructions: instructions,
            renderSize: Project.canvasSize
        ))
        return PlayableComposition(composition: composition, videoComposition: videoComposition, audioMix: audioMix, musicEnvelope: envelope)
    }

    /// Where people talk in the Short, from the measured loudness of the clips' files.
    private static func speech(in project: Project) async -> [CMTimeRange] {
        var levels: [MediaAsset.ID: AudioLevels] = [:]
        for clip in project.timeline.clips where levels[clip.assetID] == nil {
            guard let asset = project.asset(id: clip.assetID), asset.hasAudio else { continue }
            levels[clip.assetID] = await LevelCache.levels(of: asset.url)
        }
        return AudioMix.speechRanges(in: project, levels: levels)
    }

    private static func padToTime(_ track: AVMutableCompositionTrack, _ time: CMTime) {
        let end = track.segments.isEmpty ? .zero : track.timeRange.end
        if end < time {
            track.insertEmptyTimeRange(CMTimeRange(start: end, end: time))
        }
    }
}
