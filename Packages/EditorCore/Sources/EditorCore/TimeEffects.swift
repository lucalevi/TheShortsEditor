import CoreMedia
import Foundation

// Playing with time: freeze frames, instant replay, speed that changes gradually, footage filmed
// for slow motion, and clips played backwards.

// MARK: - Freeze frame

public extension Clip {
    /// How long a new freeze frame lasts.
    static let freezeDuration = CMTime(value: 3, timescale: 1)
}

public extension Project {
    /// Whether a clip is one still picture (a picture file or a freeze frame).
    func isStill(_ clip: Clip) -> Bool {
        clip.isFrozen || asset(id: clip.assetID)?.isImage == true
    }

    /// Holds the picture under `time` for a while: the main clip there is cut in two and a silent
    /// clip of that one picture goes in between, with the same framing and placement. At the very
    /// end of the Short it holds the last picture. Returns the freeze frame's id; nil on a picture
    /// or another freeze frame (they are still already).
    @discardableResult
    mutating func addFreezeFrame(at time: CMTime, duration: CMTime = Clip.freezeDuration) -> Clip.ID? {
        let time = time.snappedToFrame()
        guard !timeline.clips.isEmpty else { return nil }
        let index: Int, offset: CMTime
        if let found = timeline.locate(time) {
            (index, offset) = found
        } else {
            guard time >= self.duration else { return nil }
            index = timeline.clips.count - 1
            offset = timeline.clips[index].duration
        }
        let clip = timeline.clips[index]
        guard !isStill(clip) else { return nil }
        let atEnd = offset >= clip.duration
        // At the end there is no picture "at" the time: hold the last one.
        let source = clip.sourceTime(atOffset: atEnd ? clip.duration - .oneFrame : offset)
        var frozen = clip.piece(sourceStart: source, duration: max(duration.snappedToFrame(), Clip.minimumDuration))
        frozen.isFrozen = true
        frozen.speed = 1
        frozen.transitionOut = nil
        frozen.fadeIn = .zero
        frozen.fadeOut = .zero
        frozen.pictureFadeIn = .zero
        frozen.pictureFadeOut = .zero
        frozen.volumeKeys = []
        frozen.voiceEffect = nil
        frozen.equalizer = nil
        frozen.cleansVoice = false
        frozen.soundDetached = false
        // The motion stops with the picture: it stays as it is at that moment.
        frozen.placement = clip.placement(atSourceTime: source)
        frozen.keyframes = []
        if atEnd {
            frozen.transitionOut = clip.transitionOut
            timeline.clips[index].transitionOut = nil
            timeline.clips.insert(frozen, at: index + 1)
        } else if offset > .zero, timeline.split(at: time) != nil {
            timeline.clips.insert(frozen, at: index + 1)
        } else {
            timeline.clips.insert(frozen, at: index)
        }
        return frozen.id
    }
}

// MARK: - Instant replay

public extension Project {
    /// How much slower a replay plays.
    static let replaySpeed = 0.5

    /// Shows the part of the storyline inside `range` once more straight after itself, slower.
    /// Returns the replay's clips.
    @discardableResult
    mutating func addInstantReplay(of range: CMTimeRange, speed: Double = Project.replaySpeed) -> [Clip.ID] {
        let ids = isolate(range)
        guard let last = ids.last, let lastIndex = timeline.index(of: last) else { return [] }
        var copies = ids.compactMap { id in timeline.clips.first { $0.id == id } }.map { clip -> Clip in
            var copy = clip.piece(sourceStart: clip.sourceStart, duration: clip.duration)
            copy.transitionOut = nil
            return copy
        }
        // What came after the part now comes after the replay, with the same transition.
        copies[copies.count - 1].transitionOut = timeline.clips[lastIndex].transitionOut
        timeline.clips[lastIndex].transitionOut = nil
        timeline.clips.insert(contentsOf: copies, at: lastIndex + 1)
        for copy in copies { setSpeed(copy.speed * speed, for: copy.id) }
        return copies.map(\.id)
    }
}

// MARK: - Speed that changes gradually

/// A stretch of a clip that plays at one speed: this much of the file in this much time.
public struct SpeedSegment: Equatable, Sendable {
    public let source: CMTimeRange
    public let duration: CMTime

    public init(source: CMTimeRange, duration: CMTime) {
        self.source = source
        self.duration = duration
    }

    public var speed: Double { duration > .zero ? source.duration.seconds / duration.seconds : 1 }
}

public extension Clip {
    /// The longest a gradual speed change takes on each side of the cut.
    static let speedRampFrames: Int64 = 15
    /// The most steps of speed on each side of the cut.
    static let speedRampSteps: Int64 = 5
}

public extension Timeline {
    /// How many frames on each side of the cut after clip `index` the speed takes to change, or 0
    /// when it changes at once: the two clips have to be one recording carrying straight on at two
    /// speeds, both with `smoothSpeed`, without a transition between them.
    func speedRampFrames(afterClipAt index: Int) -> Int64 {
        guard index >= 0, index + 1 < clips.count else { return 0 }
        let a = clips[index], b = clips[index + 1]
        guard a.smoothSpeed, b.smoothSpeed, a.speed != b.speed, a.speedCurve == nil, b.speedCurve == nil, !a.isFrozen, !b.isFrozen, a.transitionOut == nil,
            a.assetID == b.assetID, abs((a.sourceRange.end - b.sourceStart).seconds) < 0.5 / Double(Project.frameRate)
        else { return 0 }
        func half(_ clip: Clip) -> Int64 { clip.duration.convertScale(Project.frameRate, method: .roundTowardNegativeInfinity).value / 2 }
        let frames = min(Clip.speedRampFrames, half(a), half(b))
        return frames >= 2 ? frames : 0
    }

    /// Whether the speed changes gradually at either end of clip `index`.
    func hasSpeedRamp(atClip index: Int) -> Bool {
        speedRampFrames(afterClipAt: index - 1) > 0 || speedRampFrames(afterClipAt: index) > 0
    }

    /// How clip `index` plays its file: one stretch at its speed, or, where the speed changes
    /// gradually into a neighbour's, a few short steps of speeds in between at that end. The
    /// stretches fill the clip's time exactly and follow on from each other in the file; across
    /// the cut the two clips' steps together show exactly what the plain clips would, so nothing
    /// else on the timeline moves. (Nothing for a freeze frame.)
    func speedSegments(forClipAt index: Int) -> [SpeedSegment] {
        let clip = clips[index]
        guard !clip.isFrozen else { return [] }
        if clip.speedCurve != nil { return clip.curveSegments }
        let framesIn = speedRampFrames(afterClipAt: index - 1), framesOut = speedRampFrames(afterClipAt: index)
        guard framesIn > 0 || framesOut > 0 else { return [SpeedSegment(source: clip.sourceRange, duration: clip.duration)] }

        let rate = Double(Project.frameRate)
        let sourceStart = clip.sourceStart.seconds, sourceEnd = clip.sourceRange.end.seconds
        // Where the steady middle begins and ends in the file.
        let middleStart = sourceStart + Double(framesIn) / rate * clip.speed
        let middleEnd = sourceEnd - Double(framesOut) / rate * clip.speed

        // (frames on the timeline, seconds of file) for each stretch, in order.
        var pieces: [(frames: Int64, source: Double)] = []
        var cursor = middleStart
        if framesIn > 0 {
            let steps = Self.rampSteps(from: clips[index - 1].speed, to: clip.speed, frames: framesIn).second
            cursor = middleStart - steps.reduce(0) { $0 + $1.source }
            pieces += steps
        }
        let start = cursor
        let middleFrames = clip.duration.convertScale(Project.frameRate, method: .roundHalfAwayFromZero).value - framesIn - framesOut
        if middleFrames > 0 { pieces.append((middleFrames, middleEnd - middleStart)) }
        if framesOut > 0 { pieces += Self.rampSteps(from: clip.speed, to: clips[index + 1].speed, frames: framesOut).first }

        var segments: [SpeedSegment] = []
        var position = start
        var from = CMTime(seconds: max(start, 0), preferredTimescale: 90000)
        for piece in pieces {
            position += piece.source
            let to = CMTime(seconds: max(position, 0), preferredTimescale: 90000)
            if to > from {
                segments.append(SpeedSegment(source: CMTimeRange(start: from, end: to), duration: CMTime(value: piece.frames, timescale: Project.frameRate)))
            }
            from = to
        }
        return segments
    }

    /// The steps of a speed change over `frames` before the cut (`first`) and as many after it
    /// (`second`): the speed goes evenly from one to the other across the whole window.
    static func rampSteps(from: Double, to: Double, frames: Int64) -> (first: [(frames: Int64, source: Double)], second: [(frames: Int64, source: Double)]) {
        let count = min(Clip.speedRampSteps, frames)
        let lengths = (0..<count).map { frames / count + ($0 < frames % count ? 1 : 0) }
        var done: Int64 = 0
        func side() -> [(frames: Int64, source: Double)] {
            lengths.map { length in
                let middle = (Double(done) + Double(length) / 2) / Double(frames * 2)
                done += length
                return (length, (from + (to - from) * middle) * Double(length) / Double(Project.frameRate))
            }
        }
        let first = side()
        return (first, side())
    }
}

// MARK: - Footage filmed for slow motion

public extension MediaAsset {
    /// Filmed at a high frame rate (an iPhone's Slo-mo: 120 or 240 pictures a second).
    var isSlowMotion: Bool { (frameRate ?? 0) >= 100 && !isImage }

    /// The speed a new clip of this file starts at: slow-motion footage plays slowed down, as far
    /// as it stays smooth (a quarter speed at most).
    var defaultSpeed: Double {
        guard isSlowMotion, let frameRate else { return 1 }
        return max(Double(Project.frameRate) / frameRate, Clip.speedRange.lowerBound)
    }

    /// The slowest speed that still shows a new picture every frame.
    var smoothestSlowSpeed: Double? {
        guard let frameRate, frameRate > Double(Project.frameRate) * 1.5, !isImage else { return nil }
        return max(Double(Project.frameRate) / frameRate, Clip.speedRange.lowerBound)
    }
}

// MARK: - Backwards

/// Says a media file is a copy of part of another file, made to play backwards.
public struct ReversedSource: Codable, Equatable, Sendable {
    public var assetID: MediaAsset.ID
    /// The part of the original the copy holds, in the original's time.
    public var range: CMTimeRange

    public init(assetID: MediaAsset.ID, range: CMTimeRange) {
        self.assetID = assetID
        self.range = range
    }

    private enum CodingKeys: String, CodingKey { case assetID, start, duration }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        assetID = try c.decode(UUID.self, forKey: .assetID)
        range = CMTimeRange(start: try c.decodeTime(forKey: .start), duration: try c.decodeTime(forKey: .duration))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(assetID, forKey: .assetID)
        try c.encode(time: range.start, forKey: .start)
        try c.encode(time: range.duration, forKey: .duration)
    }
}

/// A clip plays backwards by pointing at a backwards copy of its file (made by the app, see
/// `Reverser`), which is an ordinary media file to everything else: trimming, splitting, speed
/// and motion work on it as on any clip.
public extension Project {
    /// Files up to this long are turned around whole; of longer ones, the clip's part and a little more.
    static let reverseWholeFileLimit = CMTime(value: 60, timescale: 1)
    static let reverseMargin = CMTime(value: 3, timescale: 1)

    /// Whether a clip is playing a backwards copy.
    func isReversed(_ clip: Clip) -> Bool {
        asset(id: clip.assetID)?.reversedFrom != nil
    }

    /// Whether a clip could play backwards at all (a video, not a picture or a freeze frame).
    func canReverse(_ clip: Clip) -> Bool {
        guard let media = asset(id: clip.assetID) else { return false }
        return media.hasVideo && !media.isImage && !clip.isFrozen
    }

    /// The part of the clip's file a backwards copy should hold.
    func partToReverse(for clip: Clip) -> CMTimeRange? {
        guard canReverse(clip), let media = asset(id: clip.assetID) else { return nil }
        let whole = CMTimeRange(start: .zero, duration: media.duration)
        if media.duration <= Self.reverseWholeFileLimit { return whole }
        let range = CMTimeRange(start: clip.sourceStart - Self.reverseMargin, end: clip.sourceRange.end + Self.reverseMargin)
        return range.intersection(whole)
    }

    /// The file that shows the clip's footage the other way round, when the project has one: the
    /// original for a clip that plays backwards, or a backwards copy that holds the clip's part.
    /// `pivot` turns a time in one into the time in the other (`pivot − time`).
    func counterpart(for clip: Clip) -> (asset: MediaAsset, pivot: CMTime)? {
        guard let media = asset(id: clip.assetID) else { return nil }
        if let from = media.reversedFrom, let original = asset(id: from.assetID) {
            return (original, from.range.end)
        }
        let slack = CMTime.oneFrame
        for candidate in assets {
            guard let from = candidate.reversedFrom, from.assetID == media.id,
                from.range.start <= clip.sourceStart + slack, from.range.end >= clip.sourceRange.end - slack
            else { continue }
            return (candidate, from.range.end)
        }
        return nil
    }

    /// Turns clip `id` (main, B-roll) around using the file `counterpart(for:)` finds: it shows the
    /// same footage in the same time, the other way, and its motion and volume line turn with it.
    /// False when there is no such file yet.
    @discardableResult
    mutating func flipDirection(of id: Clip.ID) -> Bool {
        guard let clip = anyClip(id: id), let (other, pivot) = counterpart(for: clip) else { return false }
        updateAnyClip(id) { clip in
            let length = clip.sourceDuration
            var start = pivot - clip.sourceRange.end
            // The copy can be a frame shorter or longer than the part it was made from.
            start = start.clamped(.zero, max(.zero, other.duration - length))
            clip.assetID = other.id
            clip.sourceStart = start
            clip.keyframes = clip.keyframes.map { key in
                var key = key
                key.time = max(pivot - key.time, .zero)
                return key
            }.sorted { $0.time < $1.time }
            clip.volumeKeys = clip.volumeKeys.map { key in
                var key = key
                key.time = max(pivot - key.time, .zero)
                return key
            }.sorted { $0.time < $1.time }
        }
        return true
    }
}
