import CoreMedia
import Foundation

// iMovie's editing grammar, made for Shorts: ranges, putting media in, items that follow their
// clip, and copying settings from one clip to others.

// MARK: - Putting media in

/// What a file dropped on a main clip does to it.
public enum DropAction: String, CaseIterable, Identifiable, Sendable {
    /// The new media takes the clip's place, at its own length.
    case replace
    /// Takes the clip's place and length, starting at the beginning of the new media.
    case replaceFromStart
    /// Takes the clip's place and length, ending at the end of the new media.
    case replaceFromEnd
    /// Cuts the clip where it was dropped and puts the new media in between.
    case insert
    /// Over the clip from where it was dropped (B-roll).
    case overClips
    /// Over the clip, sharing the screen with it (top half).
    case splitScreen
    /// Over the clip, small in a corner.
    case pictureInPicture

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .replace: "Replace"
        case .replaceFromStart: "Replace from Start"
        case .replaceFromEnd: "Replace from End"
        case .insert: "Insert"
        case .overClips: "Over the Clip (B-roll)"
        case .splitScreen: "Split Screen"
        case .pictureInPicture: "Picture in Picture"
        }
    }

    /// Whether it works on main-storyline clips (as opposed to adding a clip over them).
    public var replacesOrInserts: Bool {
        switch self {
        case .replace, .replaceFromStart, .replaceFromEnd, .insert: true
        default: false
        }
    }
}

public extension Project {
    /// A new clip of `assetID`: the whole file (a picture for a few seconds), or `part` of it.
    func makeClip(of assetID: MediaAsset.ID, part: CMTimeRange? = nil) -> Clip? {
        guard let asset = asset(id: assetID), asset.hasVideo, asset.duration > .zero else { return nil }
        if asset.isImage {
            let length = part.map { max($0.duration.snappedToFrame(), Clip.minimumDuration) } ?? asset.defaultClipDuration
            return Clip(assetID: assetID, sourceStart: .zero, duration: length, framing: asset.defaultFraming)
        }
        var range = CMTimeRange(start: .zero, duration: asset.duration)
        if let part { range = part.intersection(range) }
        let start = range.start.snappedToFrame().clamped(.zero, max(.zero, asset.duration - Clip.minimumDuration))
        let length = max(range.duration.snappedToFrame(), Clip.minimumDuration).clamped(Clip.minimumDuration, asset.duration - start)
        var clip = Clip(assetID: assetID, sourceStart: start, duration: length, framing: asset.defaultFraming)
        // Footage filmed for slow motion starts slowed down, as it was meant to be seen.
        if asset.defaultSpeed != 1 {
            clip.speed = asset.defaultSpeed
            clip.duration = max(CMTimeMultiplyByFloat64(length, multiplier: 1 / asset.defaultSpeed).snappedToFrame(), Clip.minimumDuration)
        }
        return clip
    }

    /// Adds `part` of a file (or all of it) to the end of the storyline (iMovie's E).
    @discardableResult
    mutating func appendClip(of assetID: MediaAsset.ID, part: CMTimeRange?) -> Clip.ID? {
        guard let clip = makeClip(of: assetID, part: part) else { return nil }
        timeline.clips.append(clip)
        return clip.id
    }

    /// Puts `part` of a file (or all of it) into the storyline at `time` (iMovie's W): the clip
    /// there is cut in two and the new one goes in between. On a cut it goes in before the clip
    /// that starts there; after the end, it is added at the end.
    @discardableResult
    mutating func insertClip(of assetID: MediaAsset.ID, part: CMTimeRange? = nil, at time: CMTime) -> Clip.ID? {
        guard let clip = makeClip(of: assetID, part: part) else { return nil }
        let time = time.snappedToFrame()
        timeline.split(at: time)
        let index = timeline.locate(time)?.index ?? timeline.clips.count
        timeline.clips.insert(clip, at: index)
        return clip.id
    }

    /// Puts a file in a main clip's place (see `DropAction`). Returns the new clip's id.
    @discardableResult
    mutating func replaceClip(_ id: Clip.ID, with assetID: MediaAsset.ID, part: CMTimeRange? = nil, mode: DropAction) -> Clip.ID? {
        guard let index = timeline.index(of: id), let asset = asset(id: assetID), var clip = makeClip(of: assetID, part: part) else { return nil }
        let old = timeline.clips[index]
        switch mode {
        case .replaceFromStart, .replaceFromEnd:
            if asset.isImage {
                clip.duration = old.duration
            } else {
                let available = part ?? CMTimeRange(start: .zero, duration: asset.duration)
                let length = min(old.duration, available.duration).snappedToFrame()
                clip.duration = max(length, Clip.minimumDuration)
                clip.sourceStart = mode == .replaceFromStart ? available.start.snappedToFrame()
                    : max(.zero, available.end - clip.duration).snappedToFrame()
            }
        default:
            break
        }
        clip.transitionOut = old.transitionOut
        timeline.clips[index] = clip
        return clip.id
    }

    /// A file dropped at `time` over the clips: B-roll, split screen or picture-in-picture.
    @discardableResult
    mutating func addOverlay(of assetID: MediaAsset.ID, part: CMTimeRange?, at time: CMTime, as action: DropAction) -> Clip.ID? {
        guard let id = addOverlay(of: assetID, at: time) else { return nil }
        let isImage = asset(id: assetID)?.isImage == true
        let size = asset(id: assetID)?.displaySize ?? Project.canvasSize
        let piece = isImage ? nil : part.flatMap { makeClip(of: assetID, part: $0) }
        updateOverlay(id) { overlay in
            if let clip = piece {
                overlay.clip.sourceStart = clip.sourceStart
                overlay.clip.duration = clip.duration
            }
            switch action {
            case .splitScreen:
                overlay.layout = .top
            case .pictureInPicture:
                overlay.clip.placement = .pictureInPicture(.topRight, displaySize: size, framing: overlay.clip.framing)
            default:
                break
            }
        }
        return id
    }

    /// The parts of a file used anywhere in the Short (clips, B-roll, sounds, music), in the
    /// file's own time and merged where they overlap. Shown as the "used" mark in Media.
    func usedParts(of assetID: MediaAsset.ID) -> [CMTimeRange] {
        guard let asset = asset(id: assetID) else { return [] }
        if asset.isImage { return usageCount(of: assetID) > 0 ? [CMTimeRange(start: .zero, duration: asset.duration)] : [] }
        var ranges = (timeline.clips + overlays.map(\.clip) + sounds.map(\.clip))
            .filter { $0.assetID == assetID }
            .map(\.sourceRange)
        if let music, music.assetID == assetID, let range = musicRange {
            ranges.append(CMTimeRange(start: music.sourceStart, duration: range.duration))
        }
        let file = CMTimeRange(start: .zero, duration: asset.duration)
        return Self.mergedRanges(ranges.map { $0.intersection(file) }.filter { $0.duration > .zero })
    }

    static func mergedRanges(_ ranges: [CMTimeRange]) -> [CMTimeRange] {
        var result: [CMTimeRange] = []
        for range in ranges.sorted(by: { $0.start < $1.start }) {
            if let last = result.last, range.start <= last.end {
                result[result.count - 1] = CMTimeRange(start: last.start, end: max(last.end, range.end))
            } else {
                result.append(range)
            }
        }
        return result
    }

    /// Where the playhead can jump with "previous / next edit": the start, every cut, the edges of
    /// titles, B-roll and sounds, and the end. Sorted, without repeats.
    var editPoints: [CMTime] {
        let times = Snapping.targets(in: self, playhead: nil).map { $0.snappedToFrame() }
        return Array(Set(times.map { $0.value }).sorted()).map { CMTime(value: $0, timescale: Project.frameRate) }
            .filter { $0 <= duration }
    }

    /// The edit point before (or after) `time`.
    func editPoint(from time: CMTime, forward: Bool) -> CMTime? {
        let time = time.snappedToFrame()
        return forward ? editPoints.first { $0 > time } : editPoints.last { $0 < time }
    }
}

// MARK: - Ranges

public extension Project {
    /// Cuts the storyline at both ends of `range` and returns the clips now inside it, in order.
    @discardableResult
    mutating func isolate(_ range: CMTimeRange) -> [Clip.ID] {
        let range = Self.frameRange(range, within: duration)
        guard range.duration > .zero else { return [] }
        timeline.split(at: range.start)
        timeline.split(at: range.end)
        var ids: [Clip.ID] = []
        var start = CMTime.zero
        for clip in timeline.clips {
            let end = start + clip.duration
            if start >= range.start, end <= range.end { ids.append(clip.id) }
            start = end
        }
        return ids
    }

    /// Takes a stretch out of the storyline; what comes after closes up.
    mutating func removeRange(_ range: CMTimeRange) {
        let ids = Set(isolate(range))
        timeline.clips.removeAll { ids.contains($0.id) }
    }

    /// Keeps only the part of the touched clips that is inside `range` (iMovie's Trim to Selection):
    /// the clips the range touches lose what is outside it; other clips stay.
    mutating func trimToRange(_ range: CMTimeRange) {
        let range = Self.frameRange(range, within: duration)
        guard range.duration > .zero else { return }
        // Cutting doesn't move anything, so the touched clips' places tell what to take off after.
        var touched: [CMTimeRange] = []
        var start = CMTime.zero
        for clip in timeline.clips {
            let end = start + clip.duration
            if start < range.end, end > range.start { touched.append(CMTimeRange(start: start, end: end)) }
            start = end
        }
        isolate(range)
        var keep: [Clip] = []
        start = .zero
        for clip in timeline.clips {
            let end = start + clip.duration
            let isInside = start >= range.start && end <= range.end
            let wasTouched = touched.contains { start >= $0.start && end <= $0.end }
            if isInside || !wasTouched { keep.append(clip) }
            start = end
        }
        timeline.clips = keep
    }

    /// Changes the speed of only the part of the storyline inside `range`.
    mutating func setSpeed(_ speed: Double, in range: CMTimeRange) {
        for id in isolate(range) { setSpeed(speed, for: id) }
    }

    /// Changes the volume of only the part of the storyline inside `range`. The sound changes
    /// smoothly at the range's edges (see `Clip.continues(_:)`).
    mutating func setVolume(_ volume: Double, muted: Bool = false, in range: CMTimeRange) {
        for id in isolate(range) {
            updateAnyClip(id) { clip in
                clip.volume = min(max(volume, 0), Clip.maxVolume)
                clip.isMuted = muted
            }
        }
    }

    /// The main clip under `time` as a range (iMovie's X).
    func clipRange(at time: CMTime) -> CMTimeRange? {
        timeline.locate(time.snappedToFrame()).flatMap { timeline.range(of: timeline.clips[$0.index].id) }
    }

    /// `range` on whole frames and inside 0…`end`.
    static func frameRange(_ range: CMTimeRange, within end: CMTime) -> CMTimeRange {
        let start = range.start.snappedToFrame().clamped(.zero, end)
        let stop = range.end.snappedToFrame().clamped(start, end)
        return CMTimeRange(start: start, end: stop)
    }
}

public extension Clip {
    /// Whether this clip carries straight on from `previous` in the same file (the two were one
    /// clip, cut apart), so a change of volume between them should be a quick fade, not a jump.
    func continues(_ previous: Clip) -> Bool {
        previous.assetID == assetID && abs((previous.sourceRange.end - sourceStart).seconds) < 0.02
    }
}

// MARK: - Items that follow their clip

/// Titles, B-roll and sounds are pinned to the main clip under their start, like iMovie's
/// connected clips: moving, trimming, speeding up or removing pauses from that clip carries them
/// along. Turned off (`followsClip`), an item stays at its time on the timeline instead.
public extension Project {
    /// The main clip under an item's start, the one it is pinned to. Nil after the end.
    func anchorClip(at start: CMTime) -> Clip.ID? {
        timeline.locate(start.snappedToFrame()).map { timeline.clips[$0.index].id }
    }

    /// Moves the pinned items after an edit of the storyline, so each stays with the moment of
    /// its clip it was on in `old`. Items the edit itself moved, new items, and items whose clip
    /// is gone keep their time.
    mutating func followClips(from old: Project) {
        guard timeline != old.timeline else { return }
        let oldIDs = Set(old.timeline.clips.map(\.id))
        var starts: [CMTime] = []
        var cursor = CMTime.zero
        for clip in timeline.clips {
            starts.append(cursor)
            cursor = cursor + clip.duration
        }

        func followed(_ time: CMTime) -> CMTime? {
            guard let (index, offset) = old.timeline.locate(time.snappedToFrame()) else { return nil }
            let anchor = old.timeline.clips[index]
            let source = anchor.sourceTime(atOffset: offset)
            var nearest: (time: CMTime, distance: Double)?
            var containing: [CMTime] = []
            for (i, clip) in timeline.clips.enumerated() where clip.assetID == anchor.assetID && (clip.id == anchor.id || !oldIDs.contains(clip.id)) {
                let range = clip.sourceRange
                if range.containsTime(source) {
                    let time = (starts[i] + clip.timelineOffset(ofSourceTime: source)).snappedToFrame()
                    if clip.id == anchor.id { return time }
                    containing.append(time)
                    continue
                }
                let before = source < range.start
                let distance = before ? (range.start - source).seconds : (source - range.end).seconds
                let edge = before ? starts[i] : starts[i] + clip.duration
                if nearest == nil || distance < nearest!.distance { nearest = (edge.snappedToFrame(), distance) }
            }
            if let best = containing.min(by: { abs(($0 - time).seconds) < abs(($1 - time).seconds) }) { return best }
            return nearest?.time
        }

        let oldTitles = Dictionary(old.titles.map { ($0.id, $0.start) }) { a, _ in a }
        for i in titles.indices where titles[i].followsClip {
            guard let was = oldTitles[titles[i].id], was == titles[i].start, let now = followed(was) else { continue }
            titles[i].start = now
        }
        let oldOverlays = Dictionary(old.overlays.map { ($0.id, $0.start) }) { a, _ in a }
        for i in overlays.indices where overlays[i].followsClip {
            guard let was = oldOverlays[overlays[i].id], was == overlays[i].start, let now = followed(was) else { continue }
            overlays[i].start = now
        }
        let oldSounds = Dictionary(old.sounds.map { ($0.id, $0.start) }) { a, _ in a }
        for i in sounds.indices where sounds[i].followsClip {
            guard let was = oldSounds[sounds[i].id], was == sounds[i].start, let now = followed(was) else { continue }
            sounds[i].start = now
        }
    }

    /// Whether an item moves with its clip.
    func followsClip(_ item: TimelineItem) -> Bool {
        switch item {
        case .title(let id): title(id: id)?.followsClip ?? false
        case .overlay(let id): overlay(id: id)?.followsClip ?? false
        case .sound(let id): sound(id: id)?.followsClip ?? false
        default: false
        }
    }

    mutating func setFollowsClip(_ follows: Bool, for item: TimelineItem) {
        switch item {
        case .title(let id): updateTitle(id) { $0.followsClip = follows }
        case .overlay(let id): updateOverlay(id) { $0.followsClip = follows }
        case .sound(let id): updateSound(id) { $0.followsClip = follows }
        default: break
        }
    }

    /// Where an item starts on the timeline (titles, B-roll, sounds).
    func start(of item: TimelineItem) -> CMTime? {
        switch item {
        case .title(let id): title(id: id)?.start
        case .overlay(let id): overlay(id: id)?.start
        case .sound(let id): sound(id: id)?.start
        default: nil
        }
    }
}

// MARK: - Copy and paste settings

/// The groups of settings that can be copied from one clip to others, or reset.
public enum SettingsKind: String, CaseIterable, Identifiable, Sendable {
    /// Framing, position, size, angle, background.
    case picture
    /// Keyframes and one-click motions.
    case motion
    case speed
    /// Volume, mute and voice clean-up.
    case sound

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .picture: "Picture"
        case .motion: "Motion"
        case .speed: "Speed"
        case .sound: "Sound"
        }
    }
}

public extension Project {
    /// Gives clip `id` the `kinds` of settings `source` has. Motion is moved to the same place
    /// in the new clip (counted from its start); speed changes the clip's length, as usual.
    mutating func pasteSettings(_ kinds: Set<SettingsKind>, from source: Clip, to id: Clip.ID) {
        guard let target = anyClip(id: id) else { return }
        let targetIsImage = asset(id: target.assetID)?.isImage == true
        if kinds.contains(.speed), !targetIsImage, asset(id: source.assetID)?.isImage != true, target.speed != source.speed {
            setSpeed(source.speed, for: id)
        }
        updateAnyClip(id) { clip in
            if kinds.contains(.picture) {
                clip.framing = source.framing
                clip.placement = source.placement
                clip.background = source.background
                clip.pictureFadeIn = source.pictureFadeIn
                clip.pictureFadeOut = source.pictureFadeOut
                if !kinds.contains(.motion) { clip.keyframes = [] }
            }
            if kinds.contains(.motion) {
                clip.keyframes = source.keyframes.compactMap { keyframe in
                    let offset = source.timelineOffset(ofSourceTime: keyframe.time)
                    guard offset >= .zero, offset <= clip.duration else { return nil }
                    var moved = keyframe
                    moved.time = clip.sourceTime(atOffset: offset)
                    return moved
                }
                if source.keyframes.isEmpty, !kinds.contains(.picture) { clip.placement = source.placement }
            }
            if kinds.contains(.sound) {
                clip.volume = source.volume
                clip.isMuted = source.isMuted
                clip.cleansVoice = source.cleansVoice
                clip.fadeIn = source.fadeIn
                clip.fadeOut = source.fadeOut
                clip.voiceEffect = source.voiceEffect
                clip.equalizer = source.equalizer
                clip.copyVolumeKeys(from: source)
            }
        }
    }

    /// Puts the `kinds` of settings of clip `id` back as they are for a newly added clip.
    mutating func resetSettings(_ kinds: Set<SettingsKind>, of id: Clip.ID) {
        guard let clip = anyClip(id: id), let media = asset(id: clip.assetID) else { return }
        let isMain = timeline.index(of: id) != nil
        let isSound = sound(id: id) != nil
        if kinds.contains(.speed), clip.speed != 1, !media.isImage { setSpeed(1, for: id) }
        updateAnyClip(id) { clip in
            if kinds.contains(.picture) {
                clip.framing = isMain ? media.defaultFraming : .fill
                clip.placement = .identity
                clip.background = .blur
                clip.keyframes = []
                clip.pictureFadeIn = .zero
                clip.pictureFadeOut = .zero
            }
            if kinds.contains(.motion) { clip.keyframes = [] }
            if kinds.contains(.sound) {
                clip.volume = 1
                clip.cleansVoice = false
                clip.resetSoundShaping()
                if isMain || isSound { clip.isMuted = false }
            }
        }
    }

    /// Which `kinds` of a clip differ from how a new clip starts, so Reset has something to do.
    func changedSettings(of id: Clip.ID) -> Set<SettingsKind> {
        guard let clip = anyClip(id: id), let media = asset(id: clip.assetID) else { return [] }
        let isMain = timeline.index(of: id) != nil
        var kinds: Set<SettingsKind> = []
        if !clip.placement.isIdentity || clip.framing != (isMain ? media.defaultFraming : .fill) || (isMain && clip.background != .blur) || clip.hasPictureFades {
            kinds.insert(.picture)
        }
        if !clip.keyframes.isEmpty { kinds.insert(.motion) }
        if clip.speed != 1 { kinds.insert(.speed) }
        if clip.volume != 1 || clip.cleansVoice || clip.hasSoundShaping || (isMain && clip.isMuted) { kinds.insert(.sound) }
        return kinds
    }

    /// Gives title `id` the look, entrance and position of `source` (its words stay).
    mutating func pasteTitleDesign(from source: TextOverlay, to id: TextOverlay.ID) {
        updateTitle(id) { title in
            title.style = source.style
            title.look = source.look
            title.entrance = source.entrance
            title.verticalPosition = source.verticalPosition
            title.horizontalPosition = source.horizontalPosition
        }
    }
}
