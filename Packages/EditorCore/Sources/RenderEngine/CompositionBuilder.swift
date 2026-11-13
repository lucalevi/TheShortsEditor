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
    /// Media whose files can't be read: their clips are black and silent, the music is left out.
    public let missingAssets: Set<MediaAsset.ID>

    @MainActor
    public func makePlayerItem() -> AVPlayerItem {
        let item = AVPlayerItem(asset: composition)
        item.videoComposition = videoComposition
        item.audioMix = audioMix
        // Faster or slower clips keep the voice at its own pitch.
        item.audioTimePitchAlgorithm = .spectral
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

        var media = MediaSources(project: project)
        let captions = CaptionTrack(project: project)
        let titles = TitleTrack(project: project)
        let clipSound = AVMutableAudioMixInputParameters(track: audioTrack)
        // Volumes, volume lines and fades of the clips, with quick fades where a range of a
        // recording got another volume.
        apply(AudioMix.storylineEnvelope(project.timeline.clips), at: .zero, gain: gain, to: clipSound)

        // The main clips, back to back.
        var layers: [(range: CMTimeRange, layer: CompositorLayer)] = []
        var cursor = CMTime.zero
        for (index, clip) in project.timeline.clips.enumerated() {
            // Where the speed changes gradually into a neighbour's, the picture goes in as a few
            // short stretches at speeds in between (the sound keeps its plain step).
            // A speed curve plays as short steps, picture and sound alike.
            let segments = project.timeline.hasSpeedRamp(atClip: index) || clip.speedCurve != nil ? project.timeline.speedSegments(forClipAt: index) : nil
            let layer = try await media.layer(for: clip, at: cursor, in: videoTrack, isMain: true, segments: segments)
            if case .track = layer.source, !clip.soundDetached, clip.speedCurve != nil, let sourceAudio = try await media.audioTrack(for: clip) {
                let available = try await sourceAudio.load(.timeRange)
                var at = cursor
                for segment in SpeedSegment.joined(clip.curveSegments) {
                    let range = segment.source.intersection(available)
                    // Slivers left by rounding (a file's sound ending a hair early) are skipped.
                    if range.duration.seconds > 0.001 {
                        // Where part of a step has no sound, the rest keeps its place.
                        let ratio = segment.duration.seconds / max(segment.source.duration.seconds, 0.000_001)
                        let lead = CMTimeMultiplyByFloat64(range.start - segment.source.start, multiplier: ratio)
                        let length = CMTimeMultiplyByFloat64(range.duration, multiplier: ratio)
                        let insertAt = insertionTime(audioTrack, at + lead)
                        padToTime(audioTrack, insertAt)
                        try audioTrack.insertTimeRange(range, of: sourceAudio, at: insertAt)
                        // A step's sound ends exactly where its picture does (on a frame), not a hair after.
                        let end = range.end >= segment.source.end ? at + segment.duration : insertAt + length
                        audioTrack.scaleTimeRange(CMTimeRange(start: insertAt, duration: range.duration), toDuration: end - insertAt)
                    }
                    at = at + segment.duration
                }
            } else if case .track = layer.source, !clip.soundDetached, let sourceAudio = try await media.audioTrack(for: clip) {
                // Audio may be a little shorter than the video; insert only what exists and pad
                // so the next clip's sound still starts exactly with its picture.
                let available = try await sourceAudio.load(.timeRange)
                let range = clip.sourceRange.intersection(available)
                if range.duration > .zero {
                    let insertAt = insertionTime(audioTrack, cursor + clip.timelineOffset(ofSourceTime: range.start))
                    padToTime(audioTrack, insertAt)
                    try audioTrack.insertTimeRange(range, of: sourceAudio, at: insertAt)
                    if clip.speed != 1 { audioTrack.scaleTimeRange(CMTimeRange(start: insertAt, duration: range.duration), toDuration: clip.timelineDuration(ofSource: range.duration)) }
                }
            }
            layers.append((CMTimeRange(start: cursor, duration: clip.duration), layer))
            cursor = cursor + clip.duration
        }

        // Sound never runs past the picture (a sound longer than the Short, even by a nanosecond,
        // stalls the player).
        if !audioTrack.segments.isEmpty, audioTrack.timeRange.end > cursor {
            audioTrack.removeTimeRange(CMTimeRange(start: cursor, end: audioTrack.timeRange.end))
        }

        // Transitions: around each cut both clips are on screen. In the half before the cut the
        // next clip is needed early, in the half after it the old clip is needed late: more of
        // their files where there is more (on a track of its own), else their first or last picture.
        let spans = project.timeline.transitionSpans
        var transitionTrack: AVMutableCompositionTrack?
        var transitions: [(span: TransitionSpan, incoming: CompositorLayer, outgoing: CompositorLayer)] = []
        for span in spans {
            guard let from = layers.first(where: { $0.layer.clip.id == span.from }), let to = layers.first(where: { $0.layer.clip.id == span.to }) else { continue }
            if transitionTrack == nil { transitionTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) }
            guard let track = transitionTrack else { continue }
            let incoming = try await media.borrowedLayer(like: to.layer, before: true, half: span.half, at: span.range.start, in: track)
            let outgoing = try await media.borrowedLayer(like: from.layer, before: false, half: span.half, at: span.cut, in: track)
            transitions.append((span, incoming, outgoing))
        }
        if let transitionTrack, transitionTrack.segments.isEmpty { composition.removeTrack(transitionTrack) }

        // Overlays: each row of overlapping ones gets its own video (and sound) track.
        var mixInputs: [AVAudioMixInputParameters] = []
        let visible = project.overlays.compactMap { overlay in overlay.visibleRange(in: project).map { (overlay, $0) } }
        let rows = LanePacking.rows(visible.map { (id: $0.0.id, range: $0.1) })
        var rowVideo: [Int: AVMutableCompositionTrack] = [:]
        var rowAudio: [Int: (track: AVMutableCompositionTrack, parameters: AVMutableAudioMixInputParameters)] = [:]
        var overlayLayers: [(range: CMTimeRange, layer: CompositorLayer)] = []
        for (overlay, range) in visible {
            let row = rows[overlay.id] ?? 0
            if rowVideo[row] == nil { rowVideo[row] = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) }
            guard let track = rowVideo[row] else { continue }
            var clip = overlay.clip
            clip.duration = range.duration  // the part after the end of the Short isn't shown
            let layer = try await media.layer(for: clip, at: overlay.start, in: track, isMain: false)
            overlayLayers.append((range, layer))

            guard case .track = layer.source, clip.effectiveVolume > 0,
                  let sourceAudio = try await media.audioTrack(for: clip) else { continue }
            if rowAudio[row] == nil, let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                rowAudio[row] = (audio, AVMutableAudioMixInputParameters(track: audio))
            }
            guard let audio = rowAudio[row] else { continue }
            let source = clip.sourceRange.intersection(try await sourceAudio.load(.timeRange))
            guard source.duration > .zero else { continue }
            let at = overlay.start + clip.timelineOffset(ofSourceTime: source.start)
            try audio.track.insertTimeRange(source, of: sourceAudio, at: at)
            if clip.speed != 1 { audio.track.scaleTimeRange(CMTimeRange(start: at, duration: source.duration), toDuration: clip.timelineDuration(ofSource: source.duration)) }
            apply(overlay.clip.soundEnvelope(), at: overlay.start, gain: gain, to: audio.parameters, within: range)
        }
        for track in rowVideo.values where track.segments.isEmpty { composition.removeTrack(track) }
        mixInputs += rowAudio.values.map(\.parameters)

        // Sound effects and voice-overs: each row of overlapping ones on its own track.
        let audible = project.sounds.compactMap { sound in sound.audibleRange(in: project).map { (sound, $0) } }
        let soundRows = LanePacking.rows(audible.map { (id: $0.0.id, range: $0.1) })
        var soundTracks: [Int: (track: AVMutableCompositionTrack, parameters: AVMutableAudioMixInputParameters)] = [:]
        for (sound, range) in audible where sound.clip.effectiveVolume > 0 {
            guard let sourceAudio = try await media.audioTrack(for: sound.clip) else {
                if project.asset(id: sound.clip.assetID) != nil { media.reportMissing(sound.clip.assetID) }
                continue
            }
            let row = soundRows[sound.id] ?? 0
            if soundTracks[row] == nil, let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                soundTracks[row] = (track, AVMutableAudioMixInputParameters(track: track))
            }
            guard let target = soundTracks[row] else { continue }
            var clip = sound.clip
            clip.duration = range.duration
            let source = clip.sourceRange.intersection(try await sourceAudio.load(.timeRange))
            guard source.duration > .zero else { continue }
            let at = sound.start + clip.timelineOffset(ofSourceTime: source.start)
            try target.track.insertTimeRange(source, of: sourceAudio, at: at)
            if clip.speed != 1 { target.track.scaleTimeRange(CMTimeRange(start: at, duration: source.duration), toDuration: clip.timelineDuration(ofSource: source.duration)) }
            apply(sound.clip.soundEnvelope(), at: sound.start, gain: gain, to: target.parameters, within: range)
        }
        mixInputs += soundTracks.values.map(\.parameters)

        // One instruction for each stretch where the same clips are on screen.
        var cuts = Set(layers.flatMap { [$0.range.start, $0.range.end] })
        for (range, _) in overlayLayers { cuts.formUnion([range.start, range.end]) }
        for span in spans { cuts.formUnion([span.range.start, span.range.end]) }
        let times = cuts.filter { $0 <= cursor }.sorted()
        var instructions: [any AVVideoCompositionInstructionProtocol] = []
        for (from, to) in zip(times, times.dropFirst()) where to > from {
            guard let main = layers.first(where: { $0.range.containsTime(from) })?.layer else { continue }
            let regions = project.regions(at: from)
            let over = overlayLayers.filter { $0.range.containsTime(from) }.map { $0.layer.with(region: regions.region(for: $0.layer.clip.id, isMain: false)) }
            var drawing: TransitionDrawing?
            if let transition = transitions.first(where: { $0.span.range.containsTime(from) }) {
                let beforeCut = from < transition.span.cut
                drawing = TransitionDrawing(kind: transition.span.kind, range: transition.span.range,
                                            other: (beforeCut ? transition.incoming : transition.outgoing).with(region: regions.main), otherIsIncoming: beforeCut)
            }
            instructions.append(ShortsInstruction(
                timeRange: CMTimeRange(start: from, end: to), layers: [main.with(region: regions.main)] + over, captions: captions, titles: titles,
                transition: drawing, look: project.look
            ))
        }
        var missing = media.missing

        if audioTrack.segments.isEmpty {
            composition.removeTrack(audioTrack)
        } else {
            mixInputs.insert(clipSound, at: 0)
        }

        // The background song, on its own track, with its volume curve.
        var envelope: [VolumePoint] = []
        var songAudio: AVAssetTrack?
        if project.music != nil, project.musicRange != nil, let song = project.asset(id: project.music!.assetID) {
            songAudio = try? await media.asset(song).loadTracks(withMediaType: .audio).first
            if songAudio == nil { missing.insert(song.id) }
        }
        if let track = project.music, project.musicRange != nil, let songAudio,
           let musicTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let available = try await songAudio.load(.timeRange)
            // Once, or over and over when it loops; it may start later than the Short.
            var inserted = false
            for pass in project.musicPasses {
                let source = pass.source.intersection(available)
                guard source.duration > .zero else { continue }
                try musicTrack.insertTimeRange(source, of: songAudio, at: pass.start + (source.start - pass.source.start))
                inserted = true
            }
            if inserted {
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
        return PlayableComposition(composition: composition, videoComposition: videoComposition, audioMix: audioMix,
                                   musicEnvelope: envelope, missingAssets: missing)
    }

    /// Where people talk in the Short, from the measured loudness of the clips' files.
    private static func speech(in project: Project) async -> [CMTimeRange] {
        var levels: [MediaAsset.ID: AudioLevels] = [:]
        for clip in project.timeline.clips + project.sounds.filter({ $0.detachedFrom != nil }).map(\.clip) where levels[clip.assetID] == nil {
            guard let asset = project.asset(id: clip.assetID), asset.hasAudio else { continue }
            levels[clip.assetID] = await LevelCache.levels(of: asset.url)
        }
        return AudioMix.speechRanges(in: project, levels: levels)
    }

    /// Sets a volume curve (offsets from `start`) on a track's mix, scaled by `gain`, only
    /// inside `within` when given.
    private static func apply(_ envelope: [VolumePoint], at start: CMTime, gain: Double, to parameters: AVMutableAudioMixInputParameters,
                              within: CMTimeRange? = nil) {
        let limit = within ?? CMTimeRange(start: .zero, duration: .positiveInfinity)
        for (a, b) in zip(envelope, envelope.dropFirst()) {
            let range = CMTimeRange(start: start + a.time, end: start + b.time).intersection(limit)
            guard range.duration > .zero else { continue }
            let from = a.volume + (b.volume - a.volume) * fraction(range.start - start, a, b)
            let to = a.volume + (b.volume - a.volume) * fraction(range.end - start, a, b)
            parameters.setVolumeRamp(fromStartVolume: Float(from * gain), toEndVolume: Float(to * gain), timeRange: range)
        }
        if envelope.count == 1, let only = envelope.first { parameters.setVolume(Float(only.volume * gain), at: start + only.time) }
    }

    private static func fraction(_ time: CMTime, _ a: VolumePoint, _ b: VolumePoint) -> Double {
        let span = (b.time - a.time).seconds
        return span > 0 ? min(max((time - a.time).seconds / span, 0), 1) : 0
    }

    /// Where to put sound meant for `time`: the end of what the track already has when that is
    /// within a millisecond (scaled stretches end a hair off), so no gap or overlap of a few
    /// nanoseconds is made. Such slivers stall the player.
    private static func insertionTime(_ track: AVMutableCompositionTrack, _ time: CMTime) -> CMTime {
        guard !track.segments.isEmpty else { return time }
        let end = track.timeRange.end
        return abs((end - time).seconds) < 0.001 ? end : time
    }

    private static func padToTime(_ track: AVMutableCompositionTrack, _ time: CMTime) {
        let end = track.segments.isEmpty ? .zero : track.timeRange.end
        if end < time {
            track.insertEmptyTimeRange(CMTimeRange(start: end, end: time))
        }
    }
}

extension SpeedSegment {
    /// The shortest stretch of sound a speed curve plays at one speed: steps of a slow curve hold
    /// only a few hundredths of a second of sound (less than one AAC packet), which stalls the player.
    static let shortestSound = CMTime(value: 1, timescale: 5)

    /// Neighbouring steps joined until each lasts at least `shortestSound` in the file and on the
    /// timeline. They start and end where the steps do, so picture and sound meet at every join.
    static func joined(_ segments: [SpeedSegment]) -> [SpeedSegment] {
        var result: [SpeedSegment] = []
        var current: SpeedSegment?
        for segment in segments {
            if let open = current {
                current = SpeedSegment(source: CMTimeRange(start: open.source.start, end: segment.source.end), duration: open.duration + segment.duration)
            } else {
                current = segment
            }
            if let open = current, open.source.duration >= shortestSound, open.duration >= shortestSound {
                result.append(open)
                current = nil
            }
        }
        if let open = current {
            if let last = result.popLast() {
                result.append(SpeedSegment(source: CMTimeRange(start: last.source.start, end: open.source.end), duration: last.duration + open.duration))
            } else {
                result.append(open)
            }
        }
        return result
    }
}

/// The files a build reads, opened once each, and the layers made from them.
@MainActor
private struct MediaSources {
    let project: Project
    /// A track is only usable while its asset is alive, so they are kept for the whole build.
    private var assets: [MediaAsset.ID: AVURLAsset] = [:]
    /// Media whose files can't be read.
    private(set) var missing = Set<MediaAsset.ID>()

    init(project: Project) {
        self.project = project
    }

    mutating func asset(_ media: MediaAsset) -> AVURLAsset {
        if let known = assets[media.id] { return known }
        let asset = AVURLAsset(url: media.url)
        assets[media.id] = asset
        return asset
    }

    /// The asset `clip`'s picture is read from: its see-through copy (Remove Background), once
    /// made, else its own file.
    mutating func pictureAsset(for clip: Clip, media: MediaAsset) -> AVURLAsset {
        let url = CutoutCache.pictureURL(for: clip, media: media)
        guard url != media.url else { return asset(media) }
        let key = "cutout|\(url.path)"
        let asset = cleanedAssets[key] ?? AVURLAsset(url: url)
        cleanedAssets[key] = asset
        return asset
    }

    /// The sound `clip` plays: its file's, cleaned up (see `VoiceCleaner`) and/or through a voice
    /// effect or EQ (see `SoundProcessor`) when those have been made.
    mutating func audioTrack(for clip: Clip) async throws -> AVAssetTrack? {
        guard let media = project.asset(id: clip.assetID), media.hasAudio, !media.isImage else { return nil }
        let url = SoundProcessor.playedURL(for: clip, media: media)
        if url != media.url {
            let key = "played|\(url.path)"
            let asset = cleanedAssets[key] ?? AVURLAsset(url: url)
            cleanedAssets[key] = asset
            if let track = try? await asset.loadTracks(withMediaType: .audio).first { return track }
        }
        return try? await asset(media).loadTracks(withMediaType: .audio).first
    }

    private var cleanedAssets: [String: AVURLAsset] = [:]

    mutating func reportMissing(_ id: MediaAsset.ID) { missing.insert(id) }

    /// Puts `clip`'s picture into `track` at `start` and says how to draw it. A picture file is
    /// drawn by the compositor; missing media is black (main clip) or nothing (overlay). The main
    /// track always gets something for the whole clip, so the Short keeps its length.
    mutating func layer(for clip: Clip, at start: CMTime, in track: AVMutableCompositionTrack, isMain: Bool,
                        segments: [SpeedSegment]? = nil) async throws -> CompositorLayer {
        func make(_ source: CompositorLayer.Source, _ size: CGSize, _ transform: CGAffineTransform = .identity) -> CompositorLayer {
            CompositorLayer(source: source, clip: clip, timelineStart: start, naturalSize: size, preferredTransform: transform, isMain: isMain, region: CGRect(origin: .zero, size: Project.canvasSize))
        }
        let media = project.asset(id: clip.assetID)
        if let media, media.hasVideo, !media.isImage, clip.isFrozen {
            // A freeze frame: one picture of the video, read once.
            if isMain { try await CompositionBuilder.insertBlack(into: track, at: start, duration: clip.duration) }
            if let still = await FrameStills.still(of: CutoutCache.pictureURL(for: clip, media: media), at: clip.sourceStart) {
                return make(.frame(still), still.naturalSize, still.preferredTransform)
            }
            missing.insert(media.id)
            return make(.none, Project.canvasSize)
        }
        if let media, media.isImage {
            if isMain { try await CompositionBuilder.insertBlack(into: track, at: start, duration: clip.duration) }
            let url = CutoutCache.pictureURL(for: clip, media: media)
            if let image = StillImages.image(at: url) {
                return make(.image(url), CGSize(width: image.width, height: image.height))
            }
            missing.insert(media.id)
            return make(.none, Project.canvasSize)
        }
        // Smooth slow motion plays a copy with pictures made up in between, once it has been made.
        var smooth: (track: AVAssetTrack, shift: CMTime)?
        // (Not for a clip without its background: its own copy is played instead.)
        if let media, clip.cutout.removeBackground == nil, let copy = FrameInterpolator.existingCopy(for: clip, media: media) {
            let key = "smooth|\(copy.url.path)"
            let copyAsset = cleanedAssets[key] ?? AVURLAsset(url: copy.url)
            cleanedAssets[key] = copyAsset
            if let track = try? await copyAsset.loadTracks(withMediaType: .video).first { smooth = (track, copy.range.start) }
        }
        if let media, media.hasVideo, let original = try? await pictureAsset(for: clip, media: media).loadTracks(withMediaType: .video).first {
            let video = smooth?.track ?? original
            let shift = smooth?.shift ?? .zero
            let available = try await video.load(.timeRange)
            func inFile(_ range: CMTimeRange) -> CMTimeRange {
                let moved = CMTimeRange(start: range.start - shift, duration: range.duration)
                // The copy can be a picture shorter than the original.
                return smooth == nil ? moved : CMTimeRange(start: moved.start, end: min(moved.end, available.end))
            }
            if let segments, !segments.isEmpty {
                var at = start
                for segment in segments {
                    try track.insertTimeRange(inFile(segment.source), of: video, at: at)
                    track.scaleTimeRange(CMTimeRange(start: at, duration: inFile(segment.source).duration), toDuration: segment.duration)
                    at = at + segment.duration
                }
            } else {
                let range = inFile(clip.sourceRange)
                try track.insertTimeRange(range, of: video, at: start)
                if clip.speed != 1 || range.duration != clip.duration { track.scaleTimeRange(CMTimeRange(start: start, duration: range.duration), toDuration: clip.duration) }
            }
            let (naturalSize, preferredTransform) = try await video.load(.naturalSize, .preferredTransform)
            var layer = make(.track(track.trackID), naturalSize, preferredTransform)
            // Stabilize: only once the file's shake has been measured (the app measures it, then rebuilds).
            if clip.steadiness > 0, let path = ShakeCache.path(for: media.url) {
                layer.steadying = Steadying(path: path, clip: clip)
            }
            return layer
        }
        // A file that was moved or deleted (or can't be opened any more) can't be read.
        if let media { missing.insert(media.id) }
        if isMain { try await CompositionBuilder.insertBlack(into: track, at: start, duration: clip.duration) }
        return make(.none, Project.canvasSize)
    }

    /// The picture of a main clip for the half of a transition where the clip isn't on the main
    /// track: the `half` just before its start (`before`) or just after its end, put into `track`
    /// at `time`. Where its file has no more (or it is a still), it holds its first or last picture.
    mutating func borrowedLayer(like layer: CompositorLayer, before: Bool, half: CMTime, at time: CMTime,
                                in track: AVMutableCompositionTrack) async throws -> CompositorLayer {
        let clip = layer.clip
        func make(_ source: CompositorLayer.Source, _ size: CGSize, _ transform: CGAffineTransform) -> CompositorLayer {
            CompositorLayer(source: source, clip: clip, timelineStart: layer.timelineStart, naturalSize: size, preferredTransform: transform, isMain: true, region: layer.region,
                            steadying: layer.steadying)
        }
        // Pictures, freeze frames and missing media look the same before and after.
        guard case .track = layer.source, let media = project.asset(id: clip.assetID),
              let video = try? await pictureAsset(for: clip, media: media).loadTracks(withMediaType: .video).first else { return layer }
        let length = CMTimeMultiplyByFloat64(half, multiplier: clip.speed(atOffset: before ? .zero : clip.duration - .oneFrame))
        let source = before ? CMTimeRange(start: clip.sourceStart - length, duration: length) : CMTimeRange(start: clip.sourceRange.end, duration: length)
        let available = try await video.load(.timeRange)
        if source.start >= available.start, source.end <= available.end {
            try track.insertTimeRange(source, of: video, at: time)
            track.scaleTimeRange(CMTimeRange(start: time, duration: source.duration), toDuration: half)
            return make(.track(track.trackID), layer.naturalSize, layer.preferredTransform)
        }
        let held = before ? clip.sourceStart : clip.sourceTime(atOffset: clip.duration - .oneFrame)
        if let still = await FrameStills.still(of: CutoutCache.pictureURL(for: clip, media: media), at: held) {
            return make(.frame(still), still.naturalSize, still.preferredTransform)
        }
        return make(.none, Project.canvasSize, .identity)
    }
}

extension CompositionBuilder {
    /// Fills a stretch of the main track with black, for a picture or missing media: an empty
    /// stretch would do inside the Short, but at its end it wouldn't count towards its length.
    static func insertBlack(into track: AVMutableCompositionTrack, at start: CMTime, duration: CMTime) async throws {
        let black = try await Placeholder.blackVideoTrack()
        let second = CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 1))
        try track.insertTimeRange(second, of: black.track, at: start)
        track.scaleTimeRange(CMTimeRange(start: start, duration: second.duration), toDuration: duration)
    }
}
