import CoreMedia
import Foundation

// MARK: - Voice effects and EQ

/// A change to how a clip's sound comes out, for a joke or a mood: a robot, a chipmunk, a phone call.
public enum VoiceEffect: String, Codable, CaseIterable, Identifiable, Sendable {
    case robot, chipmunk, deep, telephone, radio, echo, megaphone, underwater

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .robot: "Robot"
        case .chipmunk: "Chipmunk"
        case .deep: "Deep"
        case .telephone: "Telephone"
        case .radio: "Radio"
        case .echo: "Echo"
        case .megaphone: "Megaphone"
        case .underwater: "Underwater"
        }
    }

    public var systemImage: String {
        switch self {
        case .robot: "cpu"
        case .chipmunk: "hare"
        case .deep: "tortoise"
        case .telephone: "phone"
        case .radio: "radio"
        case .echo: "dot.radiowaves.left.and.right"
        case .megaphone: "megaphone"
        case .underwater: "drop"
        }
    }
}

/// A tone shaping for a clip's sound (an equaliser preset).
public enum SoundEQ: String, Codable, CaseIterable, Identifiable, Sendable {
    case voice, music, lessBass

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .voice: "Clearer voice"
        case .music: "Fuller music"
        case .lessBass: "Less bass"
        }
    }

    public var hint: String {
        switch self {
        case .voice: "Less boom and mud, words easier to understand"
        case .music: "More low end and sparkle"
        case .lessBass: "Takes out rumble, wind and hum"
        }
    }
}

// MARK: - The volume line

/// A point on a clip's volume line, for the sound to rise or fall over time. `level` multiplies
/// the clip's volume (1 = the clip's volume). The time is in the source file's time, like the
/// picture's keyframes, so points stay on the same sound when the clip is split or trimmed.
public struct VolumeKey: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var time: CMTime
    public var level: Double

    public init(id: UUID = UUID(), time: CMTime, level: Double) {
        self.id = id
        self.time = time
        self.level = level
    }

    private enum CodingKeys: String, CodingKey { case id, time, level }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        time = try c.decodeTime(forKey: .time)
        level = try c.decode(Double.self, forKey: .level)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(time: time, forKey: .time)
        try c.encode(level, forKey: .level)
    }
}

public extension Clip {
    /// The longest fade a handle can make.
    static let maxFade = CMTime(value: 5, timescale: 1)
    /// How long the sound takes to change where a volume set on part of a recording begins.
    static let continuityFade = CMTime(value: 1, timescale: 5)

    /// Whether the clip's sound has been shaped in any way beyond its flat volume.
    var hasSoundShaping: Bool {
        fadeIn > .zero || fadeOut > .zero || !volumeKeys.isEmpty || voiceEffect != nil || equalizer != nil
    }

    /// Whether the sound plays through a processed copy of the file (see `SoundProcessor`).
    var needsProcessedSound: Bool { voiceEffect != nil || equalizer != nil }

    /// The fades as they are heard: each at most the clip's length, and together no longer than it.
    var heardFades: (in: CMTime, out: CMTime) {
        let fadeIn = max(fadeIn, .zero), fadeOut = max(fadeOut, .zero)
        let total = fadeIn + fadeOut
        guard total > duration, total > .zero else { return (min(fadeIn, duration), min(fadeOut, duration)) }
        let scale = duration.seconds / total.seconds
        return (CMTime(seconds: fadeIn.seconds * scale, preferredTimescale: 600), CMTime(seconds: fadeOut.seconds * scale, preferredTimescale: 600))
    }

    /// The volume-line points inside the clip, as (offset into the clip, level), in order.
    var visibleVolumeKeys: [(key: VolumeKey, offset: CMTime)] {
        volumeKeys
            .map { ($0, timelineOffset(ofSourceTime: $0.time)) }
            .filter { $0.1 >= .zero && $0.1 <= duration }
            .sorted { $0.1 < $1.1 }
    }

    /// The level from the volume-line points at `offset` into the clip (1 without points).
    func keyLevel(atOffset offset: CMTime) -> Double {
        let points = volumeKeys.map { VolumePoint(time: timelineOffset(ofSourceTime: $0.time), volume: $0.level) }.sorted { $0.time < $1.time }
        return points.isEmpty ? 1 : AudioMix.volume(at: offset, in: points)
    }

    /// How loud the clip plays at `offset` into it: volume × line × fades (0 when muted or detached).
    func soundLevel(atOffset offset: CMTime) -> Double {
        guard effectiveVolume > 0 else { return 0 }
        let fades = heardFades
        var fade = 1.0
        if fades.in > .zero, offset < fades.in { fade = min(fade, max(offset.seconds, 0) / fades.in.seconds) }
        if fades.out > .zero, offset > duration - fades.out { fade = min(fade, max((duration - offset).seconds, 0) / fades.out.seconds) }
        return effectiveVolume * keyLevel(atOffset: offset) * fade
    }

    /// The clip's volume over its own length (offsets from its start), as straight lines between
    /// points. Fades are drawn with a few steps so a fade over a sloping line stays close.
    func soundEnvelope() -> [VolumePoint] {
        guard duration > .zero else { return [] }
        let fades = heardFades
        var times: [CMTime] = [.zero, duration]
        for (_, offset) in visibleVolumeKeys { times.append(offset) }
        for (start, length) in [(CMTime.zero, fades.in), (duration - fades.out, fades.out)] where length > .zero {
            for step in 0...4 { times.append(start + CMTimeMultiplyByRatio(length, multiplier: Int32(step), divisor: 4)) }
        }
        let sorted = Set(times.map { $0.clamped(.zero, duration) }).sorted()
        return sorted.map { VolumePoint(time: $0, volume: soundLevel(atOffset: $0)) }
    }

    /// Adds a point on the volume line at `offset` into the clip, at the level the line has
    /// there. The first point also pins the line at the clip's start and end, so moving it makes
    /// a dip or a bump rather than moving the whole line. Returns its id.
    @discardableResult
    mutating func addVolumeKey(atOffset offset: CMTime, level: Double? = nil) -> VolumeKey.ID {
        let offset = offset.clamped(.zero, duration)
        let level = level ?? keyLevel(atOffset: offset)
        if volumeKeys.isEmpty {
            volumeKeys = [VolumeKey(time: sourceTime(atOffset: .zero), level: 1), VolumeKey(time: sourceTime(atOffset: duration), level: 1)]
        }
        let time = sourceTime(atOffset: offset)
        if let index = volumeKeys.firstIndex(where: { abs((timelineOffset(ofSourceTime: $0.time) - offset).seconds) < 0.5 / Double(Project.frameRate) }) {
            volumeKeys[index].level = Self.clampedLevel(level)
            return volumeKeys[index].id
        }
        let key = VolumeKey(time: time, level: Self.clampedLevel(level))
        volumeKeys.append(key)
        volumeKeys.sort { $0.time < $1.time }
        return key.id
    }

    static func clampedLevel(_ level: Double) -> Double { min(max(level, 0), Clip.maxVolume) }

    /// The fades and line of a clip cut in two at `offset`: the first part keeps the fade in, the second the fade out.
    mutating func keepFades(isFirst: Bool, isLast: Bool) {
        if !isFirst { fadeIn = .zero; pictureFadeIn = .zero }
        // The change into the next clip stays at the end of the last part.
        if !isLast { fadeOut = .zero; pictureFadeOut = .zero; transitionOut = nil }
    }

    /// Sound settings back to a newly added clip's.
    mutating func resetSoundShaping() {
        fadeIn = .zero
        fadeOut = .zero
        volumeKeys = []
        voiceEffect = nil
        equalizer = nil
    }

    /// The volume-line points of `source` placed at the same offsets into this clip.
    mutating func copyVolumeKeys(from source: Clip) {
        volumeKeys = source.volumeKeys.compactMap { key in
            let offset = source.timelineOffset(ofSourceTime: key.time)
            guard offset >= .zero, offset <= duration else { return nil }
            return VolumeKey(time: sourceTime(atOffset: offset), level: key.level)
        }
    }
}

public extension AudioMix {
    /// The volume of the main clips' sound over the whole storyline. Where a clip continues the
    /// same recording at another volume (a range had its volume changed), the sound moves to it
    /// over `Clip.continuityFade` instead of jumping.
    ///
    /// Across each of `crossfades` the clip going out fades to half by the cut and the clip coming
    /// in rises from half after it; the other half of each is heard on a track of its own.
    static func storylineEnvelope(_ clips: [Clip], crossfades: [SoundCrossfade] = []) -> [VolumePoint] {
        var points = plainStorylineEnvelope(clips)
        for fade in crossfades {
            let range = fade.span.range
            guard let out = clips.first(where: { $0.id == fade.span.from }), let into = clips.first(where: { $0.id == fade.span.to }) else { continue }
            let before = points.filter { $0.time <= range.start }
            let after = points.filter { $0.time >= range.end }
            var middle: [VolumePoint] = []
            if before.last?.time != range.start {
                middle.append(VolumePoint(time: range.start, volume: out.soundLevel(atOffset: out.duration - fade.span.half)))
            }
            middle.append(VolumePoint(time: fade.span.cut, volume: fade.outgoingLevel * 0.5))
            middle.append(VolumePoint(time: fade.span.cut, volume: fade.incomingLevel * 0.5))
            if after.first?.time != range.end {
                middle.append(VolumePoint(time: range.end, volume: into.soundLevel(atOffset: fade.span.half)))
            }
            points = before + middle + after
        }
        return points
    }

    private static func plainStorylineEnvelope(_ clips: [Clip]) -> [VolumePoint] {
        var points: [VolumePoint] = []
        var start = CMTime.zero
        var previous: Clip?
        for clip in clips {
            var envelope = clip.soundEnvelope().map { VolumePoint(time: start + $0.time, volume: $0.volume) }
            if let previous, let last = points.last, clip.continues(previous), clip.heardFades.in == .zero,
               previous.heardFades.out == .zero, last.volume != envelope.first?.volume {
                // Start from where the previous clip ended, and reach this clip's line a moment later.
                let fadeEnd = start + min(Clip.continuityFade, clip.duration)
                envelope.removeAll { $0.time < fadeEnd }
                envelope.insert(VolumePoint(time: fadeEnd, volume: clip.soundLevel(atOffset: fadeEnd - start)), at: 0)
                envelope.insert(VolumePoint(time: start, volume: last.volume), at: 0)
            }
            // The previous clip's last point and this one's first share a time: a jump.
            points += envelope
            previous = clip
            start = start + clip.duration
        }
        return points
    }

    /// Where the sound may distort: the file's loudness (dBFS, per frame) with the clip's volume
    /// applied is above `limit`. In timeline offsets from the clip's start.
    static func tooLoudRanges(of clip: Clip, levels: AudioLevels, limit: Float = AudioMix.distortionLevel) -> [CMTimeRange] {
        guard clip.effectiveVolume > 0 else { return [] }
        let frames = clip.duration.convertScale(Project.frameRate, method: .roundHalfAwayFromZero).value
        var ranges: [CMTimeRange] = []
        var runStart: Int64?
        for offset in 0...max(frames, 0) {
            var loud = false
            if offset < frames {
                let time = CMTime(value: offset, timescale: Project.frameRate)
                let index = Int(clip.sourceTime(atOffset: time).convertScale(Project.frameRate, method: .roundTowardZero).value)
                let gain = clip.soundLevel(atOffset: time)
                if index >= 0, index < levels.decibels.count, gain > 0 {
                    loud = levels.decibels[index] + Float(20 * log10(gain)) > limit
                }
            }
            if loud, runStart == nil { runStart = offset }
            if !loud, let first = runStart {
                ranges.append(CMTimeRange(start: CMTime(value: first, timescale: Project.frameRate), end: CMTime(value: offset, timescale: Project.frameRate)))
                runStart = nil
            }
        }
        return ranges
    }

    /// Steady loudness (RMS, dBFS) above which the peaks of ordinary speech or music are
    /// likely to hit full scale and crackle.
    static let distortionLevel: Float = -6
    /// Getting close: shown as a warning before it distorts.
    static let loudLevel: Float = -10
}

// MARK: - Detaching the sound

public extension Project {
    /// Puts a main clip's sound on the sound row as its own item, so it can be trimmed and moved
    /// on its own (to start before the picture, or carry on after it). The clip itself goes
    /// silent. Returns the new sound's id, or nil when the clip has no sound or is already detached.
    @discardableResult
    mutating func detachSound(of clipID: Clip.ID) -> Clip.ID? {
        guard let index = timeline.index(of: clipID) else { return nil }
        let clip = timeline.clips[index]
        guard !clip.soundDetached, let media = asset(id: clip.assetID), media.hasAudio, !media.isImage else { return nil }
        var sound = clip.piece(sourceStart: clip.sourceStart, duration: clip.duration)
        sound.framing = .fill
        sound.placement = .identity
        sound.keyframes = []
        sound.transitionOut = nil
        let start = timeline.startTime(ofClipAt: index)
        sounds.append(SoundClip(clip: sound, start: start, detachedFrom: clipID))
        timeline.clips[index].soundDetached = true
        return sound.id
    }

    /// Gives a detached clip its own sound back and removes the sound items made from it.
    mutating func reattachSound(of clipID: Clip.ID) {
        guard let index = timeline.index(of: clipID), timeline.clips[index].soundDetached else { return }
        sounds.removeAll { $0.detachedFrom == clipID }
        timeline.clips[index].soundDetached = false
    }
}

/// The sound across a transition: both clips are heard, the old one fading out as the new one
/// fades in. The old clip's sound goes on past the cut and the new one's starts before it, from
/// more of their files (like the picture), on a track of their own.
public struct SoundCrossfade: Equatable, Sendable {
    public let span: TransitionSpan
    /// The part of the incoming clip's file heard in the half before the cut.
    public let incomingSource: CMTimeRange
    /// The part of the outgoing clip's file heard in the half after the cut.
    public let outgoingSource: CMTimeRange
    /// How loud each clip plays where it meets the cut (volume, line), before the crossfade.
    public let incomingLevel: Double
    public let outgoingLevel: Double
}

public extension Project {
    /// The transitions whose sound crossfades. Only where both clips play their own sound at an
    /// even speed, without a fade of their own at the cut, and their files have the sound to
    /// borrow; elsewhere the sound simply cuts.
    var soundCrossfades: [SoundCrossfade] {
        let clips = timeline.clips
        return timeline.transitionSpans.compactMap { span in
            guard let out = clips.first(where: { $0.id == span.from }), let into = clips.first(where: { $0.id == span.to }),
                  let outgoing = borrowedSound(of: out, afterEnd: true, half: span.half),
                  let incoming = borrowedSound(of: into, afterEnd: false, half: span.half) else { return nil }
            return SoundCrossfade(span: span, incomingSource: incoming, outgoingSource: outgoing,
                                  incomingLevel: into.soundLevel(atOffset: .zero), outgoingLevel: out.soundLevel(atOffset: out.duration))
        }
    }

    /// The `half` of `clip`'s file just after its end or just before its start, if it has sound there.
    private func borrowedSound(of clip: Clip, afterEnd: Bool, half: CMTime) -> CMTimeRange? {
        guard let media = asset(id: clip.assetID), media.hasAudio, !media.isImage, !clip.isFrozen, !clip.soundDetached,
              clip.speedCurve == nil, clip.effectiveVolume > 0,
              (afterEnd ? clip.heardFades.out : clip.heardFades.in) == .zero else { return nil }
        let length = CMTimeMultiplyByFloat64(half, multiplier: clip.speed)
        let range = afterEnd ? CMTimeRange(start: clip.sourceRange.end, duration: length)
                             : CMTimeRange(start: clip.sourceStart - length, duration: length)
        guard range.start >= .zero, range.end <= media.duration else { return nil }
        return range
    }
}
