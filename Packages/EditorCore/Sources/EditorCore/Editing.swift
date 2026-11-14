import CoreMedia
import Foundation

/// One end of a clip, for trimming.
public enum ClipEdge: Sendable {
    case start, end
}

// MARK: - Trimming the main clips

public extension Project {
    /// Moves one edge of a main clip by `delta` (positive is to the right), on whole frames.
    ///
    /// The storyline is magnetic, so the clips after it close up or make room. The start edge
    /// takes off (or brings back) the beginning of the clip; the end edge, its end. A video can't
    /// go past the start or end of its file; a picture can be up to `MediaAsset.imageDuration`.
    /// Returns false when nothing could change.
    @discardableResult
    mutating func trimClip(_ id: Clip.ID, edge: ClipEdge, by delta: CMTime) -> Bool {
        guard let index = timeline.index(of: id) else { return false }
        var clip = timeline.clips[index]
        guard let limits = trimLimits(for: clip, edge: edge) else { return false }
        let applied = delta.snappedToFrame().clamped(limits.start, limits.end).snappedToFrame()
        guard applied != .zero else { return false }
        switch edge {
        case .start:
            if isVideoAsset(clip.assetID) { clip.sourceStart = clip.sourceTime(atOffset: applied) }
            clip.duration = clip.duration - applied
        case .end:
            clip.duration = clip.duration + applied
        }
        timeline.clips[index] = clip
        return true
    }

    /// How far an edge of `clip` may move, as a range of deltas.
    func trimLimits(for clip: Clip, edge: ClipEdge) -> CMTimeRange? {
        guard let asset = asset(id: clip.assetID) else { return nil }
        let shortest = clip.duration - Clip.minimumDuration
        // A freeze frame is one picture, so it can be any length, like a picture file.
        let isStill = asset.isImage || clip.isFrozen
        switch edge {
        case .start:
            // Right: until the clip is as short as allowed. Left: back to the start of the file
            // (a picture can grow as long as it may be shown).
            let leftmost = isStill ? -(MediaAsset.imageDuration - clip.duration) : -clip.timelineDuration(ofSource: clip.sourceStart)
            return CMTimeRange(start: min(leftmost, .zero), end: max(shortest, .zero))
        case .end:
            let available = isStill ? MediaAsset.imageDuration : clip.timelineDuration(ofSource: asset.duration - clip.sourceStart)
            return CMTimeRange(start: min(-shortest, .zero), end: max(available - clip.duration, .zero))
        }
    }

    /// Takes off the part of the main clip under `time` before it (`.start`, like CapCut's Q) or
    /// after it (`.end`, W). Returns where the playhead should go: where the cut was made, which
    /// for `.start` is now the clip's beginning. Nil when `time` is on a cut or outside the Short.
    @discardableResult
    mutating func trimMainClip(at time: CMTime, removing edge: ClipEdge) -> CMTime? {
        let time = time.snappedToFrame()
        guard let (index, offset) = timeline.locate(time), offset > .zero else { return nil }
        let clip = timeline.clips[index]
        let clipStart = timeline.startTime(ofClipAt: index)
        switch edge {
        case .start:
            guard clip.duration - offset >= Clip.minimumDuration else { return nil }
            trimClip(clip.id, edge: .start, by: offset)
            return clipStart
        case .end:
            guard offset >= Clip.minimumDuration else { return nil }
            trimClip(clip.id, edge: .end, by: offset - clip.duration)
            return time
        }
    }

    private func isVideoAsset(_ assetID: MediaAsset.ID) -> Bool {
        asset(id: assetID)?.isImage != true
    }
}

// MARK: - B-roll and picture-in-picture

/// A clip shown over the main clips for a while: B-roll, a picture, a second video in a corner.
///
/// Like a title, it belongs to the timeline, not to a main clip: it stays at its time when the
/// clips under it change, and the part after the end of the Short isn't shown.
public struct Overlay: Identifiable, Codable, Equatable, Sendable {
    /// What is shown and how (part of the file, placement, motion, sound).
    public var clip: Clip
    /// When it appears, on the timeline.
    public var start: CMTime
    /// Over the main clip, or sharing the screen with it (split screen).
    public var layout: OverlayLayout
    /// Moves with the main clip under its start (see `Project.followClips(from:)`).
    public var followsClip: Bool

    public init(clip: Clip, start: CMTime, layout: OverlayLayout = .free, followsClip: Bool = true) {
        self.clip = clip
        self.start = start
        self.layout = layout
        self.followsClip = followsClip
    }

    public var id: Clip.ID { clip.id }
    public var duration: CMTime { clip.duration }
    public var end: CMTime { start + clip.duration }
    public var range: CMTimeRange { CMTimeRange(start: start, duration: clip.duration) }

    /// The part that is on screen in `project`, or nil when it starts after the end.
    public func visibleRange(in project: Project) -> CMTimeRange? {
        let visible = range.intersection(CMTimeRange(start: .zero, duration: project.duration))
        return visible.duration > .zero ? visible : nil
    }

    /// The source time showing at timeline `time`.
    public func sourceTime(at time: CMTime) -> CMTime { clip.sourceTime(atOffset: time - start) }

    private enum CodingKeys: String, CodingKey { case clip, start, layout, followsClip }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clip = try c.decode(Clip.self, forKey: .clip)
        start = try c.decodeTime(forKey: .start)
        layout = try c.decodeIfPresent(OverlayLayout.self, forKey: .layout) ?? .free
        followsClip = try c.decodeIfPresent(Bool.self, forKey: .followsClip) ?? true
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(clip, forKey: .clip)
        try c.encode(time: start, forKey: .start)
        try c.encode(layout, forKey: .layout)
        try c.encode(followsClip, forKey: .followsClip)
    }
}

public extension Overlay {
    /// The longest a video is when added over the clips: B-roll is usually a few seconds.
    static let defaultVideoDuration = CMTime(value: 4, timescale: 1)
}

public extension Project {
    func overlay(id: Clip.ID) -> Overlay? {
        overlays.first { $0.id == id }
    }

    /// Adds `assetID` over the clips at `time`, covering the whole screen and without its own
    /// sound (B-roll usually plays under the voice). Near the end it starts earlier, so it isn't
    /// cut short. Returns nil for media that has no picture.
    @discardableResult
    mutating func addOverlay(of assetID: MediaAsset.ID, at time: CMTime) -> Clip.ID? {
        guard let asset = asset(id: assetID), asset.hasVideo else { return nil }
        let wanted = asset.isImage ? NewClipSettings.current.pictureLength : min(asset.duration, Overlay.defaultVideoDuration)
        let length = duration > .zero ? duration : wanted
        var start = time.snappedToFrame().clamped(.zero, length)
        if length - start < wanted { start = max(.zero, length - wanted) }
        let clip = Clip(assetID: assetID, sourceStart: .zero, duration: wanted.snappedToFrame(), framing: .fill, isMuted: true)
        overlays.append(Overlay(clip: clip, start: start.snappedToFrame()))
        return clip.id
    }

    mutating func updateOverlay(_ id: Clip.ID, _ change: (inout Overlay) -> Void) {
        guard let index = overlays.firstIndex(where: { $0.id == id }) else { return }
        change(&overlays[index])
    }

    mutating func removeOverlay(_ id: Clip.ID) {
        overlays.removeAll { $0.id == id }
    }

    /// Moves an overlay so it starts at `start`, keeping its length, on a whole frame and inside the Short.
    mutating func moveOverlay(_ id: Clip.ID, to start: CMTime) {
        let end = duration
        updateOverlay(id) { overlay in
            let latest = max(.zero, end - overlay.duration)
            overlay.start = start.snappedToFrame().clamped(.zero, latest).snappedToFrame()
        }
    }

    /// Moves one edge of an overlay by `delta`. Its other edge stays where it is on the timeline.
    @discardableResult
    mutating func trimOverlay(_ id: Clip.ID, edge: ClipEdge, by delta: CMTime) -> Bool {
        guard let overlay = overlay(id: id), let limits = trimLimits(for: overlay.clip, edge: edge) else { return false }
        var range = limits
        if edge == .start {
            // Not before the start of the Short.
            let earliest = -overlay.start
            if range.start < earliest { range = CMTimeRange(start: earliest, end: max(range.end, earliest)) }
        }
        let applied = delta.snappedToFrame().clamped(range.start, range.end).snappedToFrame()
        guard applied != .zero else { return false }
        let isImage = asset(id: overlay.clip.assetID)?.isImage == true
        updateOverlay(id) { overlay in
            switch edge {
            case .start:
                overlay.start = overlay.start + applied
                if !isImage { overlay.clip.sourceStart = overlay.clip.sourceTime(atOffset: applied) }
                overlay.clip.duration = overlay.clip.duration - applied
            case .end:
                overlay.clip.duration = overlay.clip.duration + applied
            }
        }
        return true
    }

    /// Cuts an overlay in two at `time`. Returns the id of the second half, or nil when `time`
    /// isn't inside it (with room for both halves).
    @discardableResult
    mutating func splitOverlay(_ id: Clip.ID, at time: CMTime) -> Clip.ID? {
        let time = time.snappedToFrame()
        guard let index = overlays.firstIndex(where: { $0.id == id }) else { return nil }
        let overlay = overlays[index]
        let offset = time - overlay.start
        guard offset >= Clip.minimumDuration, overlay.duration - offset >= Clip.minimumDuration else { return nil }
        let isImage = asset(id: overlay.clip.assetID)?.isImage == true
        var second = overlay.clip.piece(
            sourceStart: isImage ? overlay.clip.sourceStart : overlay.clip.sourceTime(atOffset: offset), duration: overlay.duration - offset)
        second.keepFades(isFirst: false, isLast: true)
        overlays[index].clip.duration = offset
        overlays[index].clip.keepFades(isFirst: true, isLast: false)
        overlays.insert(Overlay(clip: second, start: time, layout: overlay.layout, followsClip: overlay.followsClip), at: index + 1)
        return second.id
    }

    /// The overlays on screen at `time`, in drawing order (bottom first).
    func overlaysOnScreen(at time: CMTime) -> [Overlay] {
        overlays.filter { $0.visibleRange(in: self)?.containsTime(time) == true }
    }

    /// Changes a clip wherever it is: on the main storyline or over it.
    mutating func updateAnyClip(_ id: Clip.ID, _ change: (inout Clip) -> Void) {
        if let index = timeline.index(of: id) {
            change(&timeline.clips[index])
        } else if overlay(id: id) != nil {
            updateOverlay(id) { change(&$0.clip) }
        } else {
            updateSound(id) { change(&$0.clip) }
        }
    }

    /// A clip by id, on the main storyline, over it, or a sound.
    func anyClip(id: Clip.ID) -> Clip? {
        timeline.clips.first { $0.id == id } ?? overlay(id: id)?.clip ?? sound(id: id)?.clip
    }

    /// Where a clip (main, overlay or sound) starts on the timeline.
    func timelineStart(ofClip id: Clip.ID) -> CMTime? {
        if let index = timeline.index(of: id) { return timeline.startTime(ofClipAt: index) }
        return overlay(id: id)?.start ?? sound(id: id)?.start
    }

    /// The source time a clip (main or overlay) shows at timeline `time`, clamped to the clip.
    func sourceTime(ofClip id: Clip.ID, at time: CMTime) -> CMTime? {
        guard let clip = anyClip(id: id), let start = timelineStart(ofClip: id) else { return nil }
        let offset = (time - start).clamped(.zero, clip.duration)
        return clip.sourceTime(atOffset: offset)
    }

    /// Changes how fast a clip (main or B-roll) plays. It keeps showing the same part of its
    /// source, so it gets shorter when faster and longer when slower. Pictures have no speed.
    mutating func setSpeed(_ speed: Double, for id: Clip.ID) {
        guard let clip = anyClip(id: id), asset(id: clip.assetID)?.isImage != true, !clip.isFrozen else { return }
        let speed = min(max(speed, Clip.speedRange.lowerBound), Clip.speedRange.upperBound)
        let source = clip.sourceDuration
        updateAnyClip(id) { clip in
            clip.speed = speed
            clip.duration = clip.duration(showing: source)
        }
    }
}

// MARK: - Snapping

/// Edges of things on the timeline that a dragged edge sticks to when it comes close.
public enum Snapping {
    /// How close (in points on screen) an edge has to come to stick.
    public static let distance: Double = 8

    /// Times worth sticking to: the start and end of the Short, the cuts between clips, the edges
    /// of titles and overlays, and the playhead. The items in `excluding` don't count (so a
    /// dragged item doesn't stick to itself).
    public static func targets(in project: Project, playhead: CMTime?, excluding: Set<TimelineItem> = [], excludingMarker: Marker.ID? = nil) -> [CMTime] {
        var times: [CMTime] = [.zero, project.duration]
        var start = CMTime.zero
        for clip in project.timeline.clips {
            let end = start + clip.duration
            if !excluding.contains(.clip(clip.id)) { times += [start, end] }
            start = end
        }
        for title in project.titles where !excluding.contains(.title(title.id)) { times += [title.start, title.end] }
        for overlay in project.overlays where !excluding.contains(.overlay(overlay.id)) { times += [overlay.start, overlay.end] }
        for sound in project.sounds where !excluding.contains(.sound(sound.id)) { times += [sound.start, sound.end] }
        for marker in project.markers where marker.id != excludingMarker && marker.time <= project.duration { times.append(marker.time) }
        // The music's beats, while they are shown.
        if project.music?.showsBeats == true { times += project.timelineBeats.map(\.time) }
        if let playhead { times.append(playhead) }
        return times
    }

    /// The target nearest `time`, if one is within `tolerance`.
    public static func snap(_ time: CMTime, to targets: [CMTime], tolerance: CMTime) -> CMTime? {
        let best = targets.min { abs(($0 - time).seconds) < abs(($1 - time).seconds) }
        guard let best, abs((best - time).seconds) <= tolerance.seconds else { return nil }
        return best
    }

    /// For something keeping its length (a title or overlay being moved): the start that makes
    /// whichever of its edges is nearer a target stick to it, or nil when neither is close.
    public static func snapBlock(start: CMTime, duration: CMTime, to targets: [CMTime], tolerance: CMTime) -> CMTime? {
        let byStart = snap(start, to: targets, tolerance: tolerance)
        let byEnd = snap(start + duration, to: targets, tolerance: tolerance).map { $0 - duration }
        switch (byStart, byEnd) {
        case let (a?, b?): return abs((a - start).seconds) <= abs((b - start).seconds) ? a : b
        case let (a?, nil): return a
        case let (nil, b?): return b
        default: return nil
        }
    }
}

// MARK: - Rows

/// Puts overlapping things on separate rows, so each can be seen and grabbed.
public enum LanePacking {
    /// Each item goes on the first row (0, 1, 2…) where it doesn't overlap anything, taking the
    /// items in order of start time.
    public static func rows<ID: Hashable>(_ items: [(id: ID, range: CMTimeRange)]) -> [ID: Int] {
        var rowEnds: [CMTime] = []
        var result: [ID: Int] = [:]
        for item in items.sorted(by: { $0.range.start < $1.range.start }) {
            if let row = rowEnds.firstIndex(where: { $0 <= item.range.start }) {
                rowEnds[row] = item.range.end
                result[item.id] = row
            } else {
                rowEnds.append(item.range.end)
                result[item.id] = rowEnds.count - 1
            }
        }
        return result
    }

    /// How many rows `rows(_:)` used (at least one).
    public static func count<ID: Hashable>(_ rows: [ID: Int]) -> Int {
        (rows.values.max() ?? 0) + 1
    }
}

// MARK: - Sound effects and voice-overs

/// A sound on the timeline besides the clips' own and the music: a sound effect (whoosh, pop…)
/// or a recorded voice-over. Timed on the timeline, like titles and B-roll.
public struct SoundClip: Identifiable, Codable, Equatable, Sendable {
    /// Which part of the sound file, its volume and speed.
    public var clip: Clip
    public var start: CMTime
    /// A voice recorded over the Short: the music is lowered under it, like under speech.
    public var isVoiceOver: Bool
    /// Moves with the main clip under its start (see `Project.followClips(from:)`).
    public var followsClip: Bool
    /// The main clip whose sound this is, when it was detached from it (`Project.detachSound(of:)`).
    public var detachedFrom: Clip.ID?
    /// Turned down while someone talks, like the song: for a second song or a music bed.
    public var lowersUnderSpeech: Bool

    public init(
        clip: Clip, start: CMTime, isVoiceOver: Bool = false, followsClip: Bool = true, detachedFrom: Clip.ID? = nil,
        lowersUnderSpeech: Bool = false
    ) {
        self.lowersUnderSpeech = lowersUnderSpeech
        self.clip = clip
        self.start = start
        self.isVoiceOver = isVoiceOver
        self.followsClip = followsClip
        self.detachedFrom = detachedFrom
    }

    public var id: Clip.ID { clip.id }
    public var duration: CMTime { clip.duration }
    public var end: CMTime { start + clip.duration }
    public var range: CMTimeRange { CMTimeRange(start: start, duration: clip.duration) }

    /// The part that is heard in `project`, or nil when it starts after the end.
    public func audibleRange(in project: Project) -> CMTimeRange? {
        let audible = range.intersection(CMTimeRange(start: .zero, duration: project.duration))
        return audible.duration > .zero ? audible : nil
    }

    /// A sound file at least this long is taken for a song: it is lowered under speech when added.
    public static let songLength = CMTime(value: 20, timescale: 1)

    /// Whether it can be lowered under speech: not a voice-over or a clip's own sound (those are the speech).
    public var canLowerUnderSpeech: Bool { !isVoiceOver && detachedFrom == nil }

    private enum CodingKeys: String, CodingKey { case clip, start, isVoiceOver, followsClip, detachedFrom, lowersUnderSpeech }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clip = try c.decode(Clip.self, forKey: .clip)
        start = try c.decodeTime(forKey: .start)
        isVoiceOver = try c.decodeIfPresent(Bool.self, forKey: .isVoiceOver) ?? false
        followsClip = try c.decodeIfPresent(Bool.self, forKey: .followsClip) ?? true
        detachedFrom = try c.decodeIfPresent(UUID.self, forKey: .detachedFrom)
        lowersUnderSpeech = try c.decodeIfPresent(Bool.self, forKey: .lowersUnderSpeech) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(clip, forKey: .clip)
        try c.encode(time: start, forKey: .start)
        try c.encode(isVoiceOver, forKey: .isVoiceOver)
        try c.encode(followsClip, forKey: .followsClip)
        try c.encodeIfPresent(detachedFrom, forKey: .detachedFrom)
        if lowersUnderSpeech { try c.encode(lowersUnderSpeech, forKey: .lowersUnderSpeech) }
    }
}

public extension Project {
    func sound(id: Clip.ID) -> SoundClip? {
        sounds.first { $0.id == id }
    }

    /// Adds a sound file at `time`, whole (up to the end of the Short). Returns nil for media
    /// without sound.
    @discardableResult
    mutating func addSound(of assetID: MediaAsset.ID, at time: CMTime, isVoiceOver: Bool = false) -> Clip.ID? {
        guard let asset = asset(id: assetID), asset.hasAudio, !asset.isImage, asset.duration > .zero else { return nil }
        let start = time.snappedToFrame().clamped(.zero, max(duration - .oneFrame, .zero))
        let length = max(min(asset.duration, max(duration - start, Clip.minimumDuration)), Clip.minimumDuration).snappedToFrame()
        let clip = Clip(assetID: assetID, sourceStart: .zero, duration: min(length, asset.duration.snappedToFrame()), framing: .fill)
        // A song (a long sound file) is lowered under speech like the main song; effects aren't.
        let isSong = !isVoiceOver && !asset.hasVideo && asset.duration >= SoundClip.songLength
        sounds.append(SoundClip(clip: clip, start: start, isVoiceOver: isVoiceOver, lowersUnderSpeech: isSong))
        return clip.id
    }

    mutating func updateSound(_ id: Clip.ID, _ change: (inout SoundClip) -> Void) {
        guard let index = sounds.firstIndex(where: { $0.id == id }) else { return }
        change(&sounds[index])
    }

    mutating func removeSound(_ id: Clip.ID) {
        sounds.removeAll { $0.id == id }
    }

    mutating func moveSound(_ id: Clip.ID, to start: CMTime) {
        let end = duration
        updateSound(id) { sound in
            sound.start = start.snappedToFrame().clamped(.zero, max(.zero, end - .oneFrame)).snappedToFrame()
        }
    }

    /// Moves one edge of a sound by `delta`; its other edge stays where it is on the timeline.
    @discardableResult
    mutating func trimSound(_ id: Clip.ID, edge: ClipEdge, by delta: CMTime) -> Bool {
        guard let sound = sound(id: id), let limits = trimLimits(for: sound.clip, edge: edge) else { return false }
        var range = limits
        if edge == .start, range.start < -sound.start { range = CMTimeRange(start: -sound.start, end: max(range.end, -sound.start)) }
        let applied = delta.snappedToFrame().clamped(range.start, range.end).snappedToFrame()
        guard applied != .zero else { return false }
        updateSound(id) { sound in
            switch edge {
            case .start:
                sound.start = sound.start + applied
                sound.clip.sourceStart = sound.clip.sourceTime(atOffset: applied)
                sound.clip.duration = sound.clip.duration - applied
            case .end:
                sound.clip.duration = sound.clip.duration + applied
            }
        }
        return true
    }

    /// Cuts a sound in two at `time`. Returns the id of the second half.
    @discardableResult
    mutating func splitSound(_ id: Clip.ID, at time: CMTime) -> Clip.ID? {
        let time = time.snappedToFrame()
        guard let index = sounds.firstIndex(where: { $0.id == id }) else { return nil }
        let sound = sounds[index]
        let offset = time - sound.start
        guard offset >= Clip.minimumDuration, sound.duration - offset >= Clip.minimumDuration else { return nil }
        var second = sound.clip.piece(sourceStart: sound.clip.sourceTime(atOffset: offset), duration: sound.duration - offset)
        second.keepFades(isFirst: false, isLast: true)
        sounds[index].clip.duration = offset
        sounds[index].clip.keepFades(isFirst: true, isLast: false)
        sounds.insert(
            SoundClip(
                clip: second, start: time, isVoiceOver: sound.isVoiceOver, followsClip: sound.followsClip, detachedFrom: sound.detachedFrom,
                lowersUnderSpeech: sound.lowersUnderSpeech), at: index + 1)
        return second.id
    }

    /// Where voice-overs are heard, for lowering the music under them.
    var voiceOverRanges: [CMTimeRange] {
        sounds.filter { $0.isVoiceOver && $0.clip.effectiveVolume > 0 }.compactMap { $0.audibleRange(in: self) }
    }
}

extension Project {
    /// Takes a file out of the project, together with everything that uses it: clips, B-roll,
    /// sounds, the music and its captions.
    public mutating func removeAsset(_ id: MediaAsset.ID) {
        timeline.clips.removeAll { $0.assetID == id }
        overlays.removeAll { $0.clip.assetID == id }
        sounds.removeAll { $0.clip.assetID == id }
        if music?.assetID == id { music = nil }
        transcripts[id] = nil
        assets.removeAll { $0.id == id }
    }

    /// How many places on the timeline use this file.
    public func usageCount(of id: MediaAsset.ID) -> Int {
        timeline.clips.filter { $0.assetID == id }.count
            + overlays.filter { $0.clip.assetID == id }.count
            + sounds.filter { $0.clip.assetID == id }.count
            + (music?.assetID == id ? 1 : 0)
    }
}
