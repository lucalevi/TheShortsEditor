import CoreMedia
import Foundation

/// The background song. It starts with the Short (or at `start`) and plays until the Short (or
/// the song, unless it loops) ends.
public struct BackgroundMusic: Codable, Equatable, Sendable {
    public var assetID: MediaAsset.ID
    /// Where on the timeline the song begins.
    public var start: CMTime = .zero
    /// Plays again from its beginning when it ends before the Short does.
    public var loops: Bool = false
    /// The song's beats in its own time, found by listening or set by hand (nil: none yet, or
    /// the app's own music, whose beats are known). See `Rhythm.swift`.
    public var beats: [Beat]? = nil
    /// Beats are shown on the music and cuts snap to them.
    public var showsBeats: Bool = false
    /// Where in the song to begin, so the best part can play under the Short.
    public var sourceStart: CMTime
    /// How loud the song plays when nobody is talking, from 0 to 1.
    public var volume: Double
    /// Turn the song down while there's speech in the clips ("ducking").
    public var lowersUnderSpeech: Bool
    public var fadesIn: Bool
    public var fadesOut: Bool
    /// Set when the app made this music for a style (see `ShortStyles.swift`).
    public var mood: MusicMood?

    public init(
        assetID: MediaAsset.ID, sourceStart: CMTime = .zero, volume: Double = BackgroundMusic.defaultVolume,
        lowersUnderSpeech: Bool = true, fadesIn: Bool = true, fadesOut: Bool = true, mood: MusicMood? = nil
    ) {
        self.mood = mood
        self.assetID = assetID
        self.sourceStart = sourceStart
        self.volume = volume
        self.lowersUnderSpeech = lowersUnderSpeech
        self.fadesIn = fadesIn
        self.fadesOut = fadesOut
    }

    /// Songs are mastered much louder than speech is recorded, so they start well below full.
    public static let defaultVolume = 0.5
    /// Under speech the song drops to this fraction of its volume (about −14 dB).
    public static let loweredFraction = 0.2
    public static let fadeInDuration = CMTime(value: 1, timescale: 1)
    public static let fadeOutDuration = CMTime(value: 2, timescale: 1)
    /// How long the song takes to go down before speech, and back up after it.
    public static let lowerDuration = CMTime(value: 1, timescale: 4)
    public static let raiseDuration = CMTime(value: 6, timescale: 10)
}

/// A point of a volume curve: the volume at `time`, with straight lines between points.
public struct VolumePoint: Equatable, Sendable {
    public var time: CMTime
    public var volume: Double

    public init(time: CMTime, volume: Double) {
        self.time = time
        self.volume = volume
    }
}

public extension Project {
    /// Uses `assetID` (a sound file, or a video's sound) as the background song, starting at its beginning.
    mutating func setMusic(_ assetID: MediaAsset.ID) {
        guard let asset = asset(id: assetID), asset.hasAudio else { return }
        if music?.assetID == assetID { return }
        music = BackgroundMusic(assetID: assetID)
    }

    /// Chooses where in the song to begin, on a whole frame and leaving at least a second to play.
    mutating func setMusicStart(_ start: CMTime) {
        guard let track = music, let song = asset(id: track.assetID) else { return }
        let latest = max(.zero, song.duration - CMTime(value: 1, timescale: 1))
        music?.sourceStart = CMTimeClampToRange(start.snappedToFrame(), range: CMTimeRange(start: .zero, end: latest)).snappedToFrame()
    }

    /// Where the song plays on the timeline, or nil without music (or with nothing to play under).
    var musicRange: CMTimeRange? { musicRange(through: duration) }

    /// Where the song would play if the Short lasted until `end`.
    func musicRange(through end: CMTime) -> CMTimeRange? {
        guard let track = music, let song = asset(id: track.assetID), track.start < end else { return nil }
        let room = end - track.start
        let length = track.loops && song.duration > .zero ? room : min(room, song.duration - track.sourceStart)
        return length > .zero ? CMTimeRange(start: track.start, duration: length) : nil
    }

    /// Whether the song stops before the Short does.
    var musicEndsEarly: Bool {
        guard let range = musicRange else { return false }
        return range.end < duration
    }
}

/// Works out how the sound is mixed: where people talk, and the song's volume over time.
public enum AudioMix {
    /// Gaps between words shorter than this don't let the song come back up, so it doesn't pump.
    public static let bridgedGap = CMTime(value: 1, timescale: 2)
    /// Shorter bursts of sound (a cough, a click) don't lower the song.
    public static let shortestSpeech = CMTime(value: 6, timescale: 30)
    /// Quieter than this (dBFS) is never speech, even in a file that is quiet throughout.
    public static let quietestSpeech: Float = -45

    /// Where on the timeline the clips have someone talking (or other clear sound), from the
    /// loudness of their files. A muted clip has none. Ranges are in order and don't overlap.
    public static func speechRanges(in project: Project, levels: [MediaAsset.ID: AudioLevels]) -> [CMTimeRange] {
        var frames: [Int64] = [] // timeline frame numbers with sound
        // The main clips, and the sound detached from them (it is still the clips' own sound).
        var placed: [(clip: Clip, start: CMTime)] = []
        var cursor = CMTime.zero
        for clip in project.timeline.clips {
            placed.append((clip, cursor))
            cursor = cursor + clip.duration
        }
        for sound in project.sounds where sound.detachedFrom != nil {
            if let range = sound.audibleRange(in: project) {
                var clip = sound.clip
                clip.duration = range.duration
                placed.append((clip, sound.start))
            }
        }
        for (clip, start) in placed {
            let clipStart = start.convertScale(Project.frameRate, method: .roundHalfAwayFromZero).value
            let clipFrames = clip.duration.convertScale(Project.frameRate, method: .roundHalfAwayFromZero).value
            guard clip.effectiveVolume > 0, let audio = levels[clip.assetID] else { continue }
            let threshold = max(audio.suggestedThreshold, quietestSpeech)
            let sourceFirst = clip.sourceStart.convertScale(Project.frameRate, method: .roundHalfAwayFromZero).value
            for offset in 0..<clipFrames {
                let index =
                    clip.speedCurve == nil
                    ? Int(sourceFirst + Int64((Double(offset) * clip.speed).rounded(.down)))
                    : Int((clip.sourceTime(atOffset: CMTime(value: offset, timescale: Project.frameRate)).seconds * Double(Project.frameRate)).rounded(.down))
                if index >= 0, index < audio.decibels.count, audio.decibels[index] >= threshold {
                    frames.append(clipStart + offset)
                }
            }
        }
        let bridge = bridgedGap.convertScale(Project.frameRate, method: .roundHalfAwayFromZero).value
        let shortest = shortestSpeech.convertScale(Project.frameRate, method: .roundHalfAwayFromZero).value
        var runs: [(start: Int64, end: Int64)] = []
        for frame in Set(frames).sorted() {
            if let last = runs.last, frame - last.end <= bridge {
                runs[runs.count - 1].end = frame + 1
            } else {
                runs.append((frame, frame + 1))
            }
        }
        let speech = runs.filter { $0.end - $0.start >= shortest }.map {
            CMTimeRange(start: CMTime(value: $0.start, timescale: Project.frameRate), end: CMTime(value: $0.end, timescale: Project.frameRate))
        }
        // Voice-overs count as speech for their whole length.
        let voiceOvers = project.voiceOverRanges
        guard !voiceOvers.isEmpty else { return speech }
        var merged: [CMTimeRange] = []
        for range in (speech + voiceOvers).sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, range.start <= last.end + bridgedGap {
                merged[merged.count - 1] = CMTimeRange(start: last.start, end: max(last.end, range.end))
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    /// The song's volume over the timeline: its own volume, faded in and out, and lowered around
    /// `speech`. Empty without music.
    public static func musicEnvelope(for project: Project, speech: [CMTimeRange]) -> [VolumePoint] {
        guard let track = project.music, let range = project.musicRange else { return [] }
        let speech = track.lowersUnderSpeech ? speech.compactMap { range.intersection($0).duration > .zero ? $0 : nil } : []
        let down = BackgroundMusic.lowerDuration, up = BackgroundMusic.raiseDuration
        let fadeIn = track.fadesIn ? min(BackgroundMusic.fadeInDuration, CMTimeMultiplyByRatio(range.duration, multiplier: 1, divisor: 3)) : .zero
        let fadeOut = track.fadesOut ? min(BackgroundMusic.fadeOutDuration, CMTimeMultiplyByRatio(range.duration, multiplier: 1, divisor: 3)) : .zero

        func lowered(at t: CMTime) -> Double { loweredFactor(at: t, speech: speech) }
        func faded(at t: CMTime) -> Double {
            var f = 1.0
            if fadeIn > .zero, t < range.start + fadeIn { f = min(f, (t - range.start).seconds / fadeIn.seconds) }
            if fadeOut > .zero, t > range.end - fadeOut { f = min(f, (range.end - t).seconds / fadeOut.seconds) }
            return max(f, 0)
        }

        var times: [CMTime] = [range.start, range.end, range.start + fadeIn, range.end - fadeOut]
        for r in speech {
            times += [r.start - down, r.start, r.end, r.end + up]
        }
        let sorted = Set(times.map { CMTimeClampToRange($0, range: range) }).sorted()
        var points: [VolumePoint] = []
        for t in sorted {
            let volume = track.volume * lowered(at: t) * faded(at: t)
            // Drop points in the middle of a flat stretch.
            if points.count >= 2, points[points.count - 1].volume == volume, points[points.count - 2].volume == volume {
                points[points.count - 1].time = t
            } else {
                points.append(VolumePoint(time: t, volume: volume))
            }
        }
        return points
    }

    /// How much a sound that lowers under speech is turned down at `time` (1: not at all, down
    /// to `BackgroundMusic.loweredFraction`), going down just before speech and back up after it.
    public static func loweredFactor(at t: CMTime, speech: [CMTimeRange]) -> Double {
        let down = BackgroundMusic.lowerDuration, up = BackgroundMusic.raiseDuration
        var factor = 1.0
        for r in speech {
            let f: Double
            if t <= r.start - down || t >= r.end + up {
                f = 1
            } else if t < r.start {
                f = 1 - (1 - BackgroundMusic.loweredFraction) * (t - (r.start - down)).seconds / down.seconds
            } else if t <= r.end {
                f = BackgroundMusic.loweredFraction
            } else {
                f = BackgroundMusic.loweredFraction + (1 - BackgroundMusic.loweredFraction) * (t - r.end).seconds / up.seconds
            }
            factor = min(factor, f)
        }
        return factor
    }

    /// A sound's own volume curve (times from its start, which is at `start` on the timeline),
    /// lowered around `speech` (timeline times) like the song.
    public static func lowered(_ envelope: [VolumePoint], startingAt start: CMTime, speech: [CMTimeRange]) -> [VolumePoint] {
        guard let first = envelope.first?.time, let last = envelope.last?.time, !speech.isEmpty else { return envelope }
        let down = BackgroundMusic.lowerDuration, up = BackgroundMusic.raiseDuration
        var times = envelope.map(\.time)
        for r in speech { times += [r.start - down, r.start, r.end, r.end + up].map { $0 - start } }
        let sorted = Set(times.map { $0.clamped(first, last) }).sorted()
        return sorted.map { t in
            VolumePoint(time: t, volume: volume(at: t, in: envelope) * loweredFactor(at: start + t, speech: speech))
        }
    }

    /// The volume a curve has at `time` (straight lines between points, flat outside them).
    public static func volume(at time: CMTime, in envelope: [VolumePoint]) -> Double {
        guard let first = envelope.first, let last = envelope.last else { return 0 }
        if time <= first.time { return first.volume }
        if time >= last.time { return last.volume }
        let after = envelope.firstIndex { $0.time > time }!
        let a = envelope[after - 1], b = envelope[after]
        let span = (b.time - a.time).seconds
        guard span > 0 else { return b.volume }
        return a.volume + (b.volume - a.volume) * (time - a.time).seconds / span
    }
}

/// Measures loudness the way broadcasters and YouTube do (ITU-R BS.1770 / EBU R128): K-weighted,
/// in 400 ms blocks, with quiet blocks left out. Feed it 48 kHz stereo, in any number of pieces.
public struct LoudnessMeter: Sendable {
    /// What YouTube plays Shorts at. Louder uploads are turned down; quieter ones are not turned up.
    public static let youTubeTarget = -14.0
    /// Peaks are kept at least this far below full scale (dBFS) so the AAC encoder doesn't clip them.
    public static let peakCeiling = -1.0
    /// Never turn quiet sound up by more than this (dB), so a near-silent Short doesn't become all hiss.
    public static let maximumBoost = 20.0

    public static let sampleRate = 48_000

    private struct Biquad: Sendable {
        let b0, b1, b2, a1, a2: Double
        var z1 = 0.0, z2 = 0.0

        mutating func process(_ x: Double) -> Double {
            let y = b0 * x + z1
            z1 = b1 * x - a1 * y + z2
            z2 = b2 * x - a2 * y
            return y
        }
    }

    // The K-weighting filters for 48 kHz from BS.1770-4: a high-shelf, then a high-pass.
    private static let shelf = Biquad(b0: 1.53512485958697, b1: -2.69169618940638, b2: 1.19839281085285, a1: -1.69065929318241, a2: 0.73248077421585)
    private static let highPass = Biquad(b0: 1, b1: -2, b2: 1, a1: -1.99004745483398, a2: 0.99007225036621)

    private var filters = [[shelf, highPass], [shelf, highPass]]
    /// Sum of squared, weighted samples in each 100 ms step (both channels together).
    private var steps: [Double] = []
    private var current = 0.0
    private var inCurrent = 0
    public private(set) var peak: Float = 0

    public init() {}

    /// Adds interleaved stereo samples.
    public mutating func add(interleaved samples: UnsafeBufferPointer<Float>) {
        let stepLength = Self.sampleRate / 10
        var index = 0
        while index + 1 < samples.count {
            for channel in 0..<2 {
                let x = samples[index + channel]
                peak = max(peak, abs(x))
                var y = Double(x)
                y = filters[channel][0].process(y)
                y = filters[channel][1].process(y)
                current += y * y
            }
            inCurrent += 1
            if inCurrent == stepLength {
                steps.append(current)
                current = 0
                inCurrent = 0
            }
            index += 2
        }
    }

    public mutating func add(interleaved samples: [Float]) {
        samples.withUnsafeBufferPointer { add(interleaved: $0) }
    }

    /// Integrated loudness in LUFS, or nil when there was no sound loud enough to measure.
    public var integratedLoudness: Double? {
        let stepLength = Double(Self.sampleRate / 10)
        guard steps.count >= 4 else { return nil }
        // 400 ms blocks overlapping by 75%: four 100 ms steps each.
        let blocks = (0...(steps.count - 4)).map { i in (steps[i] + steps[i + 1] + steps[i + 2] + steps[i + 3]) / (4 * stepLength) }
        func loudness(_ meanSquare: Double) -> Double { -0.691 + 10 * log10(meanSquare) }
        let audible = blocks.filter { $0 > 0 && loudness($0) > -70 }
        guard !audible.isEmpty else { return nil }
        let relativeGate = loudness(audible.reduce(0, +) / Double(audible.count)) - 10
        let gated = audible.filter { loudness($0) > relativeGate }
        guard !gated.isEmpty else { return nil }
        return loudness(gated.reduce(0, +) / Double(gated.count))
    }

    /// The gain (a factor, 1 = unchanged) that brings the sound to `target` LUFS without pushing
    /// peaks over `peakCeiling` or boosting by more than `maximumBoost`.
    public func normalizingGain(target: Double = LoudnessMeter.youTubeTarget) -> Double {
        guard let loudness = integratedLoudness, peak > 0 else { return 1 }
        let wanted = min(target - loudness, Self.maximumBoost)
        let headroom = Self.peakCeiling - 20 * log10(Double(peak))
        return pow(10, min(wanted, headroom) / 20)
    }
}

extension BackgroundMusic {
    private enum CodingKeys: String, CodingKey {
        case assetID, sourceStart, volume, lowersUnderSpeech, fadesIn, fadesOut, mood
        case start, loops, beats, showsBeats
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        assetID = try c.decode(UUID.self, forKey: .assetID)
        sourceStart = try c.decodeTime(forKey: .sourceStart)
        volume = try c.decode(Double.self, forKey: .volume)
        lowersUnderSpeech = try c.decode(Bool.self, forKey: .lowersUnderSpeech)
        fadesIn = try c.decode(Bool.self, forKey: .fadesIn)
        fadesOut = try c.decode(Bool.self, forKey: .fadesOut)
        mood = try? c.decodeIfPresent(MusicMood.self, forKey: .mood)
        start = c.contains(.start) ? try c.decodeTime(forKey: .start) : .zero
        loops = try c.decodeIfPresent(Bool.self, forKey: .loops) ?? false
        beats = try? c.decodeIfPresent([Beat].self, forKey: .beats)
        showsBeats = try c.decodeIfPresent(Bool.self, forKey: .showsBeats) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(assetID, forKey: .assetID)
        try c.encode(time: sourceStart, forKey: .sourceStart)
        try c.encode(volume, forKey: .volume)
        try c.encode(lowersUnderSpeech, forKey: .lowersUnderSpeech)
        try c.encode(fadesIn, forKey: .fadesIn)
        try c.encode(fadesOut, forKey: .fadesOut)
        try c.encodeIfPresent(mood, forKey: .mood)
        if start > .zero { try c.encode(time: start, forKey: .start) }
        if loops { try c.encode(loops, forKey: .loops) }
        try c.encodeIfPresent(beats, forKey: .beats)
        if showsBeats { try c.encode(showsBeats, forKey: .showsBeats) }
    }
}
