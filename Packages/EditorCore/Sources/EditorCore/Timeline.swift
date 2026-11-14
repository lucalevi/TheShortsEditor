import CoreMedia
import Foundation

/// A piece of a source file placed on the timeline.
public struct Clip: Identifiable, Codable, Equatable, Sendable {
    public internal(set) var id: UUID
    public var assetID: MediaAsset.ID
    /// Where in the source file this clip begins.
    public var sourceStart: CMTime
    /// How long the clip lasts on the timeline. At a speed other than 1 it shows
    /// `duration × speed` of its source (see `sourceDuration`).
    public var duration: CMTime
    public var framing: Framing
    /// How loud the clip's own sound plays: 1 is as recorded, up to `Clip.maxVolume`.
    public var volume: Double
    /// Silences the clip without forgetting its volume.
    public var isMuted: Bool
    /// Moved, resized or turned on top of the framing. Used when the clip has no keyframes.
    public var placement: Placement
    /// Motion over time, sorted by time (in the source file's time). Empty for a still picture.
    public var keyframes: [Keyframe]
    /// What shows around the picture where it doesn't cover the canvas.
    public var background: ClipBackground
    /// How fast it plays: 2 is twice as fast (half as long), 0.5 is slow motion. Voices keep their pitch.
    public var speed: Double
    /// Whether the clip's sound is cleaned up (background noise removed, voice kept).
    public var cleansVoice: Bool
    /// How long the sound takes to come up at the start and go down at the end (timeline time).
    public var fadeIn: CMTime
    public var fadeOut: CMTime
    /// Points on the volume line, for sound that rises and falls (empty: flat at `volume`).
    public var volumeKeys: [VolumeKey]
    public var voiceEffect: VoiceEffect?
    public var equalizer: SoundEQ?
    /// The sound has been moved to its own item on the sound row (`SoundClip.detachedFrom`),
    /// so the clip itself is silent.
    public var soundDetached: Bool
    /// How this clip changes into the next main clip (nil: a plain cut). See `Transitions.swift`.
    public var transitionOut: ClipTransition?
    /// A freeze frame: the clip shows the one picture at `sourceStart` for its whole length, silent.
    public var isFrozen: Bool
    /// How long the picture takes to appear and to go (timeline time). Used for clips over the main ones.
    public var pictureFadeIn: CMTime
    public var pictureFadeOut: CMTime
    /// Where the clip carries on from a neighbour of the same recording at another speed, the
    /// speed changes gradually instead of in one jump (see `Timeline.speedSegments(forClipAt:)`).
    public var smoothSpeed: Bool
    /// Colour adjustments and filter (see `Look.swift`).
    public var look: ClipLook
    /// How strongly camera shake is smoothed out, 0…1 (0: Stabilize is off). See `Stabilization.swift`.
    public var steadiness: Double
    /// The placement and motion came from the Short's style, so another style may replace them.
    public var styledMotion: Bool = false
    /// Speeds up and slows down by itself in a named shape, on top of `speed` (see `SpeedCurves.swift`).
    public var speedCurve: SpeedCurve? = nil
    /// Slow motion made smooth: pictures in between are made up (see `FrameInterpolator`).
    public var smoothSlowMotion: Bool = false
    /// How the picture comes in at its start and goes at its end (see `ClipAnimation.swift`).
    public var animationIn: ClipAnimation? = nil
    public var animationOut: ClipAnimation? = nil
    /// Effects on the picture (shake, flash, glitch…), see `Effects.swift`.
    public var effects: [ClipEffect] = []
    /// Remove Background, green screen, mask and blend mode (see `Cutouts.swift`).
    public var cutout = ClipCutout()
    /// The colour behind the picture when `background` is `.color`.
    public var backgroundColor: RGBA = .white

    public static let maxVolume = 2.0
    /// No clip is shorter than this, so it can still be seen and grabbed on the timeline.
    public static let minimumDuration = CMTime(value: 3, timescale: Project.frameRate)
    public static let speedRange: ClosedRange<Double> = 0.25...4
    /// The speeds offered with one click.
    public static let speedPresets: [Double] = [0.5, 1, 1.25, 1.5, 2]

    public init(
        id: UUID = UUID(), assetID: MediaAsset.ID, sourceStart: CMTime, duration: CMTime, framing: Framing = .fill,
        volume: Double = 1, isMuted: Bool = false, placement: Placement = .identity, keyframes: [Keyframe] = [],
        background: ClipBackground = .blur, speed: Double = 1, cleansVoice: Bool = false,
        fadeIn: CMTime = .zero, fadeOut: CMTime = .zero, volumeKeys: [VolumeKey] = [],
        voiceEffect: VoiceEffect? = nil, equalizer: SoundEQ? = nil, soundDetached: Bool = false,
        transitionOut: ClipTransition? = nil, isFrozen: Bool = false, pictureFadeIn: CMTime = .zero, pictureFadeOut: CMTime = .zero,
        smoothSpeed: Bool = true, look: ClipLook = ClipLook(), steadiness: Double = 0
    ) {
        self.id = id
        self.assetID = assetID
        self.sourceStart = sourceStart
        self.duration = duration
        self.framing = framing
        self.volume = volume
        self.isMuted = isMuted
        self.placement = placement
        self.keyframes = keyframes
        self.background = background
        self.speed = speed
        self.cleansVoice = cleansVoice
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
        self.volumeKeys = volumeKeys
        self.voiceEffect = voiceEffect
        self.equalizer = equalizer
        self.soundDetached = soundDetached
        self.transitionOut = transitionOut
        self.isFrozen = isFrozen
        self.pictureFadeIn = pictureFadeIn
        self.pictureFadeOut = pictureFadeOut
        self.smoothSpeed = smoothSpeed
        self.look = look
        self.steadiness = steadiness
    }

    /// How much of the source the clip shows (nothing but one picture for a freeze frame).
    public var sourceDuration: CMTime {
        if isFrozen { return .zero }
        if speedCurve != nil { return CMTime(seconds: curveSource(atOffset: duration.seconds), preferredTimescale: 90000) }
        return speed == 1 ? duration : CMTimeMultiplyByFloat64(duration, multiplier: speed).convertScale(600, method: .roundHalfAwayFromZero)
    }

    public var sourceRange: CMTimeRange { CMTimeRange(start: sourceStart, duration: sourceDuration) }

    /// The source time playing `offset` into the clip.
    public func sourceTime(atOffset offset: CMTime) -> CMTime {
        if isFrozen { return sourceStart }
        if speedCurve != nil { return sourceStart + CMTime(seconds: curveSource(atOffset: offset.seconds), preferredTimescale: 90000) }
        return speed == 1 ? sourceStart + offset : sourceStart + CMTimeMultiplyByFloat64(offset, multiplier: speed)
    }

    /// How far into the clip a source time plays (it may be outside the clip).
    public func timelineOffset(ofSourceTime time: CMTime) -> CMTime {
        if isFrozen { return .zero }
        if speedCurve != nil { return CMTime(seconds: curveOffset(ofSource: (time - sourceStart).seconds), preferredTimescale: 90000) }
        return speed == 1 ? time - sourceStart : CMTimeMultiplyByFloat64(time - sourceStart, multiplier: 1 / speed)
    }

    /// A stretch of the source as it lasts on the timeline.
    public func timelineDuration(ofSource duration: CMTime) -> CMTime {
        if speedCurve != nil, !isFrozen {
            let source = sourceDuration.seconds
            let average = source > 0 ? source / self.duration.seconds : speed
            return CMTimeMultiplyByFloat64(duration, multiplier: 1 / average)
        }
        return speed == 1 ? duration : CMTimeMultiplyByFloat64(duration, multiplier: 1 / speed)
    }

    /// The volume actually played (before the volume line and fades).
    public var effectiveVolume: Double { isMuted || soundDetached || isFrozen ? 0 : volume }

    /// Another piece of the same source with the same settings (framing, sound, placement and
    /// motion), e.g. after a split.
    public func piece(id: UUID = UUID(), sourceStart: CMTime, duration: CMTime) -> Clip {
        var piece = self
        piece.id = id
        piece.sourceStart = sourceStart
        piece.duration = duration
        return piece
    }
}

/// The main storyline: clips play back to back with no gaps ("magnetic"), so removing a clip
/// closes the hole and moving one shifts the others.
public struct Timeline: Codable, Equatable, Sendable {
    public var clips: [Clip] = []

    public init(clips: [Clip] = []) {
        self.clips = clips
    }

    public var duration: CMTime {
        clips.reduce(.zero) { $0 + $1.duration }
    }

    public func index(of id: Clip.ID) -> Int? {
        clips.firstIndex { $0.id == id }
    }

    public func startTime(ofClipAt index: Int) -> CMTime {
        clips[..<index].reduce(.zero) { $0 + $1.duration }
    }

    /// Where the clip sits on the timeline.
    public func range(of id: Clip.ID) -> CMTimeRange? {
        guard let index = index(of: id) else { return nil }
        return CMTimeRange(start: startTime(ofClipAt: index), duration: clips[index].duration)
    }

    /// The clip playing at `time` and how far into it `time` is. A time exactly on a cut belongs
    /// to the clip that starts there.
    public func locate(_ time: CMTime) -> (index: Int, offset: CMTime)? {
        guard time >= .zero else { return nil }
        var start = CMTime.zero
        for (index, clip) in clips.enumerated() {
            let end = start + clip.duration
            if time < end { return (index, time - start) }
            start = end
        }
        return nil
    }

    /// Removes a clip and closes the gap.
    public mutating func remove(_ id: Clip.ID) {
        clips.removeAll { $0.id == id }
    }

    /// Moves a clip so it ends up at `destination` (an index into the timeline after removal).
    public mutating func move(_ id: Clip.ID, to destination: Int) {
        guard let from = index(of: id) else { return }
        let clip = clips.remove(at: from)
        clips.insert(clip, at: min(max(destination, 0), clips.count))
    }

    /// Cuts the clip under `time` in two, at the nearest frame. Returns the id of the new second
    /// half, or nil when `time` is on an existing cut or outside the timeline.
    @discardableResult
    public mutating func split(at time: CMTime) -> Clip.ID? {
        let time = time.snappedToFrame()
        guard let (index, offset) = locate(time), offset > .zero else { return nil }
        var first = clips[index]
        guard offset < first.duration else { return nil }
        var second = first.piece(sourceStart: first.sourceTime(atOffset: offset), duration: first.duration - offset)
        if let curve = first.speedCurve {
            // Each half plays its own part of the shape.
            let middle = curve.from + (curve.to - curve.from) * offset.seconds / first.duration.seconds
            first.speedCurve?.to = middle
            second.speedCurve?.from = middle
        }
        first.duration = offset
        // Effects at the start stay with the first part, those at the end with the second.
        first.effects.removeAll { $0.part == .end }
        second.effects.removeAll { $0.part == .start }
        second.effects = second.effects.map {
            var effect = $0; effect.id = UUID(); return effect
        }
        first.keepFades(isFirst: true, isLast: false)
        second.keepFades(isFirst: false, isLast: true)
        clips[index] = first
        clips.insert(second, at: index + 1)
        return second.id
    }
}

extension Clip {
    private enum CodingKeys: String, CodingKey {
        case id, assetID, sourceStart, duration, framing, volume, isMuted, placement, keyframes, background, speed, cleansVoice
        case fadeIn, fadeOut, volumeKeys, voiceEffect, equalizer, soundDetached
        case transitionOut, isFrozen, pictureFadeIn, pictureFadeOut, smoothSpeed
        case look, steadiness, styledMotion
        case speedCurve, smoothSlowMotion, animationIn, animationOut, effects, cutout, backgroundColor
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        assetID = try c.decode(UUID.self, forKey: .assetID)
        sourceStart = try c.decodeTime(forKey: .sourceStart)
        duration = try c.decodeTime(forKey: .duration)
        framing = try c.decode(Framing.self, forKey: .framing)
        volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? 1
        isMuted = try c.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        placement = try c.decodeIfPresent(Placement.self, forKey: .placement) ?? .identity
        keyframes = try c.decodeIfPresent([Keyframe].self, forKey: .keyframes) ?? []
        // Shorts saved before backgrounds existed had black bars: keep them looking the same.
        background = try c.decodeIfPresent(ClipBackground.self, forKey: .background) ?? .black
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? 1
        cleansVoice = try c.decodeIfPresent(Bool.self, forKey: .cleansVoice) ?? false
        fadeIn = c.contains(.fadeIn) ? try c.decodeTime(forKey: .fadeIn) : .zero
        fadeOut = c.contains(.fadeOut) ? try c.decodeTime(forKey: .fadeOut) : .zero
        volumeKeys = try c.decodeIfPresent([VolumeKey].self, forKey: .volumeKeys) ?? []
        voiceEffect = try? c.decodeIfPresent(VoiceEffect.self, forKey: .voiceEffect)
        equalizer = try? c.decodeIfPresent(SoundEQ.self, forKey: .equalizer)
        soundDetached = try c.decodeIfPresent(Bool.self, forKey: .soundDetached) ?? false
        transitionOut = try? c.decodeIfPresent(ClipTransition.self, forKey: .transitionOut)
        isFrozen = try c.decodeIfPresent(Bool.self, forKey: .isFrozen) ?? false
        pictureFadeIn = c.contains(.pictureFadeIn) ? try c.decodeTime(forKey: .pictureFadeIn) : .zero
        pictureFadeOut = c.contains(.pictureFadeOut) ? try c.decodeTime(forKey: .pictureFadeOut) : .zero
        smoothSpeed = try c.decodeIfPresent(Bool.self, forKey: .smoothSpeed) ?? true
        look = (try? c.decodeIfPresent(ClipLook.self, forKey: .look)) ?? ClipLook()
        steadiness = try c.decodeIfPresent(Double.self, forKey: .steadiness) ?? 0
        styledMotion = try c.decodeIfPresent(Bool.self, forKey: .styledMotion) ?? false
        speedCurve = try? c.decodeIfPresent(SpeedCurve.self, forKey: .speedCurve)
        smoothSlowMotion = try c.decodeIfPresent(Bool.self, forKey: .smoothSlowMotion) ?? false
        animationIn = try? c.decodeIfPresent(ClipAnimation.self, forKey: .animationIn)
        animationOut = try? c.decodeIfPresent(ClipAnimation.self, forKey: .animationOut)
        effects = (try? c.decodeIfPresent([ClipEffect].self, forKey: .effects)) ?? []
        cutout = (try? c.decodeIfPresent(ClipCutout.self, forKey: .cutout)) ?? ClipCutout()
        backgroundColor = (try? c.decodeIfPresent(RGBA.self, forKey: .backgroundColor)) ?? .white
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(assetID, forKey: .assetID)
        try c.encode(time: sourceStart, forKey: .sourceStart)
        try c.encode(time: duration, forKey: .duration)
        try c.encode(framing, forKey: .framing)
        try c.encode(volume, forKey: .volume)
        try c.encode(isMuted, forKey: .isMuted)
        try c.encode(placement, forKey: .placement)
        try c.encode(keyframes, forKey: .keyframes)
        try c.encode(background, forKey: .background)
        try c.encode(speed, forKey: .speed)
        try c.encode(cleansVoice, forKey: .cleansVoice)
        if fadeIn > .zero { try c.encode(time: fadeIn, forKey: .fadeIn) }
        if fadeOut > .zero { try c.encode(time: fadeOut, forKey: .fadeOut) }
        if !volumeKeys.isEmpty { try c.encode(volumeKeys, forKey: .volumeKeys) }
        try c.encodeIfPresent(voiceEffect, forKey: .voiceEffect)
        try c.encodeIfPresent(equalizer, forKey: .equalizer)
        if soundDetached { try c.encode(soundDetached, forKey: .soundDetached) }
        try c.encodeIfPresent(transitionOut, forKey: .transitionOut)
        if isFrozen { try c.encode(isFrozen, forKey: .isFrozen) }
        if pictureFadeIn > .zero { try c.encode(time: pictureFadeIn, forKey: .pictureFadeIn) }
        if pictureFadeOut > .zero { try c.encode(time: pictureFadeOut, forKey: .pictureFadeOut) }
        if !smoothSpeed { try c.encode(smoothSpeed, forKey: .smoothSpeed) }
        if look != ClipLook() { try c.encode(look, forKey: .look) }
        if steadiness > 0 { try c.encode(steadiness, forKey: .steadiness) }
        if styledMotion { try c.encode(styledMotion, forKey: .styledMotion) }
        try c.encodeIfPresent(speedCurve, forKey: .speedCurve)
        if smoothSlowMotion { try c.encode(smoothSlowMotion, forKey: .smoothSlowMotion) }
        try c.encodeIfPresent(animationIn, forKey: .animationIn)
        try c.encodeIfPresent(animationOut, forKey: .animationOut)
        if !effects.isEmpty { try c.encode(effects, forKey: .effects) }
        if !cutout.isEmpty { try c.encode(cutout, forKey: .cutout) }
        if backgroundColor != .white { try c.encode(backgroundColor, forKey: .backgroundColor) }
    }
}
