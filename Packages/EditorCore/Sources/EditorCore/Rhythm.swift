import CoreMedia
import Foundation

// Rhythm: the beats of the music (known for the app's own music, found by listening for any
// other song), cuts that snap to them, Cut to the Beat, and music that starts later or loops.

// MARK: - Beats

/// One beat of a song, in the song's own time.
public struct Beat: Codable, Equatable, Hashable, Sendable {
    public var time: CMTime
    /// The first beat of a bar (a stronger beat).
    public var isBarStart: Bool

    public init(time: CMTime, isBarStart: Bool = false) {
        self.time = time
        self.isBarStart = isBarStart
    }

    private enum CodingKeys: String, CodingKey { case time, bar }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        time = try c.decodeTime(forKey: .time)
        isBarStart = try c.decodeIfPresent(Bool.self, forKey: .bar) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(time: time, forKey: .time)
        if isBarStart { try c.encode(true, forKey: .bar) }
    }
}

/// A beat placed on the timeline.
public struct TimelineBeat: Equatable, Sendable {
    public var time: CMTime
    public var isBarStart: Bool
    /// Which beat of its bar it is (0 is the bar's first).
    public var indexInBar: Int
}

/// Which beats Cut to the Beat cuts on.
public enum BeatSpacing: String, CaseIterable, Identifiable, Sendable {
    case everyBeat, everyOtherBeat, everyBar

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .everyBeat: "Every Beat"
        case .everyOtherBeat: "Every Other Beat"
        case .everyBar: "Every Bar"
        }
    }

    func includes(_ beat: TimelineBeat) -> Bool {
        switch self {
        case .everyBeat: true
        case .everyOtherBeat: beat.indexInBar % 2 == 0
        case .everyBar: beat.indexInBar == 0
        }
    }
}

public extension MusicMood {
    /// The beats of the app's music for this mood (it is built bar by bar from time 0, four beats a bar).
    func beats(upTo length: CMTime) -> [Beat] {
        let interval = 60 / tempo
        let count = Int(length.seconds / interval)
        guard count >= 0 else { return [] }
        return (0...count).map { Beat(time: CMTime(seconds: Double($0) * interval, preferredTimescale: 48_000), isBarStart: $0 % 4 == 0) }
            .filter { $0.time < length }
    }
}

/// Finds the beats of a song from how strongly new sounds start over time (its "onsets"):
/// the steadiest pulse between 70 and 180 beats a minute, then where its bars begin. Most
/// music has one tempo, so the beats are an even grid.
public enum BeatFinder {
    public static let tempoRange: ClosedRange<Double> = 70...180

    /// `onsets` and `bass` (onsets of the low notes, for where bars begin) are measured `rate`
    /// times a second from the start of the song. Empty when there is no clear pulse.
    public static func beats(onsets: [Float], bass: [Float], rate: Double, length: CMTime) -> [Beat] {
        let count = onsets.count
        guard count > Int(rate * 3), let loudest = onsets.max(), loudest > 0 else { return [] }
        let envelope = onsets.map { Double($0 / loudest) }
        let mean = envelope.reduce(0, +) / Double(count)
        let centred = envelope.map { $0 - mean }

        // The tempo: the lag at which the onsets repeat best, preferring tempos near 120.
        let shortest = Int((rate * 60 / tempoRange.upperBound).rounded(.down)), longest = Int((rate * 60 / tempoRange.lowerBound).rounded(.up))
        guard longest < count / 2 else { return [] }
        var bestLag = shortest, bestScore = -Double.infinity
        for lag in shortest...longest {
            var sum = 0.0
            for i in 0..<(count - lag) { sum += centred[i] * centred[i + lag] }
            let bpm = rate * 60 / Double(lag)
            let preference = exp(-0.5 * pow(log2(bpm / 120) / 0.9, 2))
            let score = sum / Double(count - lag) * preference
            if score > bestScore { bestScore = score; bestLag = lag }
        }
        guard bestScore > 0 else { return [] }

        // The exact period and where the beats fall: the grid that lands on the most onset strength.
        func combScore(period: Double, phase: Double) -> Double {
            var sum = 0.0, n = 0
            var position = phase
            while position < Double(count - 1) {
                let i = Int(position.rounded())
                // Take the strongest of the frame and its neighbours, so a grid a little off still counts.
                sum += max(envelope[max(i - 1, 0)], envelope[i], envelope[min(i + 1, count - 1)])
                n += 1
                position += period
            }
            return n > 0 ? sum / Double(n) : 0
        }
        var period = Double(bestLag), phase = 0.0, best = -1.0
        var candidate = Double(bestLag) - 1
        while candidate <= Double(bestLag) + 1 {
            var p = 0.0
            while p < candidate {
                let score = combScore(period: candidate, phase: p)
                if score > best { best = score; period = candidate; phase = p }
                p += 0.5
            }
            candidate += 0.05
        }

        // Fit the grid to the onsets it found: each beat's nearest peak, then the straight line
        // through them, so a long song doesn't drift off the beat.
        var indices: [Double] = [], peaks: [Double] = []
        var k = 0.0
        while phase + k * period < Double(count - 1) {
            let centre = Int((phase + k * period).rounded())
            let low = max(centre - 3, 0), high = min(centre + 3, count - 1)
            if let peak = (low...high).max(by: { envelope[$0] < envelope[$1] }), envelope[peak] > 0.1 {
                indices.append(k)
                peaks.append(Double(peak))
            }
            k += 1
        }
        if indices.count >= 4 {
            let n = Double(indices.count)
            let meanK = indices.reduce(0, +) / n, meanP = peaks.reduce(0, +) / n
            var covariance = 0.0, variance = 0.0
            for (x, y) in zip(indices, peaks) { covariance += (x - meanK) * (y - meanP); variance += (x - meanK) * (x - meanK) }
            if variance > 0 {
                let fitted = covariance / variance
                if abs(fitted - period) < 1 {
                    period = fitted
                    phase = meanP - fitted * meanK
                }
            }
        }
        while phase - period >= 0 { phase -= period }
        while phase < 0 { phase += period }

        var positions: [Double] = []
        var position = phase
        while position < Double(count) { positions.append(position); position += period }
        // Past the measured stretch (rounding), keep the grid going to the end of the song.
        let end = length.seconds * rate
        while position < end { positions.append(position); position += period }
        guard !positions.isEmpty else { return [] }

        // Bars: of the four ways of grouping the beats in fours, the one with the strongest low notes.
        let bassLoudest = max(bass.max() ?? 0, 0.000_001)
        var barOffset = 0, strongest = -1.0
        for offset in 0..<4 {
            var sum = 0.0, n = 0
            for (index, position) in positions.enumerated() where index % 4 == offset {
                let i = Int(position.rounded())
                guard i < bass.count else { continue }
                sum += Double(bass[i] / bassLoudest)
                n += 1
            }
            let average = n > 0 ? sum / Double(n) : 0
            if average > strongest { strongest = average; barOffset = offset }
        }
        return positions.enumerated().map { index, position in
            Beat(time: CMTime(seconds: position / rate, preferredTimescale: 48_000), isBarStart: index % 4 == barOffset)
        }.filter { $0.time < length }
    }
}

// MARK: - The music on the timeline

public extension Project {
    /// The song's beats in its own time: found or set by hand, else the app's music's own.
    var songBeats: [Beat] {
        guard let music, let song = asset(id: music.assetID) else { return [] }
        if let beats = music.beats { return beats }
        return music.mood?.beats(upTo: song.duration) ?? []
    }

    /// Whether the song's beats are known (found, set by hand or the app's own music).
    var hasBeats: Bool { !songBeats.isEmpty }

    /// The time in the song playing at timeline `time` (nil outside the music).
    func songTime(atTimeline time: CMTime) -> CMTime? {
        guard let music, let range = musicRange, let song = asset(id: music.assetID),
              time >= range.start, time <= range.end else { return nil }
        let into = time - music.start
        let firstPass = song.duration - music.sourceStart
        if into < firstPass || !music.loops || song.duration <= .zero { return music.sourceStart + into }
        let seconds = (into - firstPass).seconds.truncatingRemainder(dividingBy: song.duration.seconds)
        return CMTime(seconds: seconds, preferredTimescale: 48_000)
    }

    /// Where each pass of the song plays: (timeline start, song part). One pass unless it loops.
    var musicPasses: [(start: CMTime, source: CMTimeRange)] { musicPasses(through: duration) }

    /// The same if the Short lasted until `end`.
    func musicPasses(through end: CMTime) -> [(start: CMTime, source: CMTimeRange)] {
        guard let music, let range = musicRange(through: end), let song = asset(id: music.assetID) else { return [] }
        var passes: [(start: CMTime, source: CMTimeRange)] = []
        var at = range.start
        var sourceStart = music.sourceStart
        while at < range.end {
            let length = min(song.duration - sourceStart, range.end - at)
            guard length > .zero else { break }
            passes.append((at, CMTimeRange(start: sourceStart, duration: length)))
            at = at + length
            sourceStart = .zero
            if !music.loops { break }
        }
        return passes
    }

    /// The song's beats where they play on the timeline, in order.
    var timelineBeats: [TimelineBeat] { timelineBeats(through: duration) }

    /// The same if the Short lasted until `end` (where it could grow to).
    func timelineBeats(through end: CMTime) -> [TimelineBeat] {
        let beats = songBeats
        guard !beats.isEmpty else { return [] }
        var placed: [(time: CMTime, isBarStart: Bool)] = []
        for pass in musicPasses(through: end) {
            for beat in beats where beat.time >= pass.source.start && beat.time < pass.source.end {
                placed.append((pass.start + beat.time - pass.source.start, beat.isBarStart))
            }
        }
        // Count the beats of each bar, so every other beat and bars can be picked.
        var result: [TimelineBeat] = []
        var index = 0
        for beat in placed {
            if beat.isBarStart { index = 0 }
            result.append(TimelineBeat(time: beat.time, isBarStart: beat.isBarStart, indexInBar: index))
            index += 1
        }
        return result
    }

    /// Moves the music on the timeline so it starts at `start` (a whole frame; at least a second
    /// before the end of the Short).
    mutating func setMusicTimelineStart(_ start: CMTime) {
        guard music != nil else { return }
        let latest = max(.zero, duration - CMTime(value: 1, timescale: 1))
        music?.start = start.snappedToFrame().clamped(.zero, latest).snappedToFrame()
    }

    /// Adds a beat by hand where the music plays at timeline `time`. False outside the music.
    @discardableResult
    mutating func addBeat(atTimeline time: CMTime) -> Bool {
        guard let songTime = songTime(atTimeline: time.snappedToFrame()) else { return false }
        var beats = songBeats
        let tolerance = 0.5 / Double(Project.frameRate)
        guard !beats.contains(where: { abs(($0.time - songTime).seconds) < tolerance }) else { return false }
        beats.append(Beat(time: songTime))
        beats.sort { $0.time < $1.time }
        music?.beats = beats
        music?.showsBeats = true
        return true
    }

    /// Removes the beat nearest timeline `time`, if one is within `tolerance`. False when none is.
    @discardableResult
    mutating func removeBeat(nearTimeline time: CMTime, tolerance: CMTime = CMTime(value: 4, timescale: Project.frameRate)) -> Bool {
        guard let nearest = timelineBeats.min(by: { abs(($0.time - time).seconds) < abs(($1.time - time).seconds) }),
              abs((nearest.time - time).seconds) <= tolerance.seconds,
              let songTime = songTime(atTimeline: nearest.time) else { return false }
        var beats = songBeats
        guard let index = beats.indices.min(by: { abs((beats[$0].time - songTime).seconds) < abs((beats[$1].time - songTime).seconds) }) else { return false }
        beats.remove(at: index)
        music?.beats = beats
        return true
    }

    /// Forgets beats set by hand or found, going back to none (or the app's music's own).
    mutating func resetBeats() {
        music?.beats = nil
    }
}

// MARK: - Cut to the Beat

public extension Project {
    /// Trims the main clips so every cut, and the end of the Short, lands on a beat of the
    /// music (`spacing` picks which beats). Each cut goes to the beat nearest where it is, as
    /// far as the clip's footage allows and never shorter than a clip may be; a cut with no
    /// beat near it (outside the music) stays. Returns how many cuts moved.
    @discardableResult
    mutating func cutToBeat(_ spacing: BeatSpacing) -> Int {
        // The end of the Short may move past where it ends now.
        let beats = timelineBeats(through: Project.maxDuration).filter { spacing.includes($0) }.map { $0.time.snappedToFrame() }
        guard beats.count >= 2 else { return 0 }
        // How far a cut may move: one gap between the chosen beats.
        let gaps = zip(beats, beats.dropFirst()).map { ($1 - $0).seconds }.sorted()
        let reach = gaps[gaps.count / 2]
        let shortest = max(Clip.minimumDuration, CMTime(value: 1, timescale: 4))

        var moved = 0
        var start = CMTime.zero
        for index in timeline.clips.indices {
            let clip = timeline.clips[index]
            let end = start + clip.duration
            var longest = end
            if let limits = trimLimits(for: clip, edge: .end) { longest = end + limits.end }
            let candidates = beats.filter { $0 - start >= shortest && $0 <= longest && abs(($0 - end).seconds) <= reach }
            if let beat = candidates.min(by: { abs(($0 - end).seconds) < abs(($1 - end).seconds) }), beat != end {
                timeline.clips[index].duration = beat - start
                moved += 1
            }
            start = start + timeline.clips[index].duration
        }
        return moved
    }
}
