import CoreMedia
import Foundation

// Speed curves: a clip that speeds up and slows down by itself, in one of a few named shapes
// (like CapCut's Montage, Hero, Bullet…). The clip keeps its own speed; the shape multiplies it
// over the clip's length. It plays as short steps of one speed each (`Clip.curveStepFrames`),
// so the composition, the sound and every source ↔ timeline mapping agree exactly.

/// A named shape of speed over a clip.
public enum SpeedCurveShape: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Fast, slow, fast, slow, fast: a pulsing rhythm for quick montages.
    case montage
    /// Quick, then a long slow moment in the middle, then quick again.
    case hero
    /// Very fast into a very slow middle, then very fast out.
    case bullet
    /// Normal, then a quick burst in the middle, then normal.
    case jumpCut
    /// Starts very fast and settles to normal.
    case flashIn
    /// Plays normally, then rushes out at the end.
    case flashOut

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .montage: "Montage"
        case .hero: "Hero"
        case .bullet: "Bullet"
        case .jumpCut: "Jump Cut"
        case .flashIn: "Flash In"
        case .flashOut: "Flash Out"
        }
    }

    public var hint: String {
        switch self {
        case .montage: "Fast and slow in turn, for quick montages"
        case .hero: "Quick, then a slow hero moment in the middle"
        case .bullet: "Rushes into a very slow middle and out again"
        case .jumpCut: "A quick burst in the middle"
        case .flashIn: "Starts very fast and settles"
        case .flashOut: "Plays normally, then rushes out"
        }
    }

    /// The shape: (position through the clip 0…1, speed factor), straight lines between points.
    public var points: [(position: Double, factor: Double)] {
        switch self {
        case .montage: [(0, 2.5), (0.2, 0.6), (0.4, 2.5), (0.6, 0.6), (0.8, 2.5), (1, 0.8)]
        case .hero: [(0, 1.8), (0.3, 1.8), (0.42, 0.3), (0.62, 0.3), (0.74, 1.8), (1, 1.8)]
        case .bullet: [(0, 2.5), (0.2, 0.2), (0.8, 0.2), (1, 2.5)]
        case .jumpCut: [(0, 1), (0.38, 1), (0.48, 5), (0.56, 5), (0.66, 1), (1, 1)]
        case .flashIn: [(0, 5), (0.3, 1), (1, 1)]
        case .flashOut: [(0, 1), (0.7, 1), (1, 5)]
        }
    }

    /// The speed factor at `position` (0…1) through the shape.
    public func factor(at position: Double) -> Double {
        let points = self.points
        let u = min(max(position, 0), 1)
        guard let after = points.firstIndex(where: { $0.position >= u }) else { return points.last!.factor }
        if after == 0 { return points[0].factor }
        let a = points[after - 1], b = points[after]
        let span = b.position - a.position
        return span > 0 ? a.factor + (b.factor - a.factor) * (u - a.position) / span : b.factor
    }
}

/// The shape a clip plays, and which part of it: a whole clip plays all of it (0…1); after a
/// split each half plays its own part, so the two together still play the whole shape.
public struct SpeedCurve: Codable, Equatable, Hashable, Sendable {
    public var shape: SpeedCurveShape
    public var from: Double
    public var to: Double

    public init(_ shape: SpeedCurveShape, from: Double = 0, to: Double = 1) {
        self.shape = shape
        self.from = from
        self.to = to
    }

    /// The factor `fraction` (0…1) of the way through the clip.
    public func factor(atFraction fraction: Double) -> Double {
        shape.factor(at: from + (to - from) * fraction)
    }

    /// The average factor over the clip's part of the shape.
    public var averageFactor: Double {
        let samples = 200
        var total = 0.0
        for i in 0..<samples { total += factor(atFraction: (Double(i) + 0.5) / Double(samples)) }
        return total / Double(samples)
    }
}

public extension Clip {
    /// How many frames each step of a speed curve lasts.
    static let curveStepFrames: Int64 = 3
    /// The slowest and fastest a speed curve may play (its shape times the clip's speed).
    static let curveSpeedRange: ClosedRange<Double> = 0.1...10

    /// The steps a clip with a speed curve plays in: this many frames at this speed, in order.
    /// Empty without a curve (and for a freeze frame).
    var curveSteps: [(frames: Int64, speed: Double)] {
        guard let speedCurve, !isFrozen else { return [] }
        let total = max(duration.convertScale(Project.frameRate, method: .roundHalfAwayFromZero).value, 1)
        var steps: [(frames: Int64, speed: Double)] = []
        var done: Int64 = 0
        while done < total {
            let length = min(Self.curveStepFrames, total - done)
            let fraction = (Double(done) + Double(length) / 2) / Double(total)
            let speed = min(max(speed * speedCurve.factor(atFraction: fraction), Self.curveSpeedRange.lowerBound), Self.curveSpeedRange.upperBound)
            steps.append((length, speed))
            done += length
        }
        return steps
    }

    /// The stretches of the file a clip with a speed curve plays, one per step.
    var curveSegments: [SpeedSegment] {
        var segments: [SpeedSegment] = []
        var from = sourceStart.seconds
        for step in curveSteps {
            let to = from + Double(step.frames) / Double(Project.frameRate) * step.speed
            segments.append(
                SpeedSegment(
                    source: CMTimeRange(start: CMTime(seconds: from, preferredTimescale: 90000), end: CMTime(seconds: to, preferredTimescale: 90000)),
                    duration: CMTime(value: step.frames, timescale: Project.frameRate)
                ))
            from = to
        }
        return segments
    }

    /// Seconds of file played `offset` seconds into a clip with a speed curve (past either end,
    /// at the speed of the step there).
    internal func curveSource(atOffset offset: Double) -> Double {
        let steps = curveSteps
        guard let first = steps.first, let last = steps.last else { return offset * speed }
        if offset <= 0 { return offset * first.speed }
        var timeline = 0.0, source = 0.0
        for step in steps {
            let length = Double(step.frames) / Double(Project.frameRate)
            if offset <= timeline + length { return source + (offset - timeline) * step.speed }
            timeline += length
            source += length * step.speed
        }
        return source + (offset - timeline) * last.speed
    }

    /// The inverse: how far into a clip with a speed curve `source` seconds of file play.
    internal func curveOffset(ofSource source: Double) -> Double {
        let steps = curveSteps
        guard let first = steps.first, let last = steps.last else { return source / speed }
        if source <= 0 { return source / first.speed }
        var timeline = 0.0, played = 0.0
        for step in steps {
            let length = Double(step.frames) / Double(Project.frameRate)
            let stepSource = length * step.speed
            if source <= played + stepSource { return timeline + (source - played) / step.speed }
            timeline += length
            played += stepSource
        }
        return timeline + (source - played) / last.speed
    }

    /// The speed playing `offset` into the clip (its speed curve's step there, else its speed).
    func speed(atOffset offset: CMTime) -> Double {
        guard speedCurve != nil, !isFrozen else { return speed }
        let steps = curveSteps
        var frame = offset.convertScale(Project.frameRate, method: .roundTowardNegativeInfinity).value
        for step in steps {
            if frame < step.frames { return step.speed }
            frame -= step.frames
        }
        return steps.last?.speed ?? speed
    }

    /// How much file a second of the clip shows on average (its speed, unless it has a curve).
    var averageSpeed: Double {
        guard speedCurve != nil, !isFrozen, duration > .zero else { return speed }
        return sourceDuration.seconds / duration.seconds
    }

    /// How long the clip lasts when it shows `source` of its file at its speed and curve.
    func duration(showing source: CMTime) -> CMTime {
        let average = speed * (speedCurve?.averageFactor ?? 1)
        return max(CMTimeMultiplyByFloat64(source, multiplier: 1 / average).snappedToFrame(), Clip.minimumDuration)
    }
}

public extension Project {
    /// Gives a main clip a speed curve (nil takes it away). It keeps showing the same part of its
    /// file, so its length changes. Pictures and freeze frames have no speed.
    mutating func setSpeedCurve(_ shape: SpeedCurveShape?, for id: Clip.ID) {
        guard let index = timeline.index(of: id), !isStill(timeline.clips[index]),
            let media = asset(id: timeline.clips[index].assetID)
        else { return }
        var clip = timeline.clips[index]
        let source = clip.sourceDuration
        clip.speedCurve = shape.map { SpeedCurve($0) }
        clip.duration = clip.duration(showing: source)
        // Steps round the curve a little: never ask for more than the file has.
        let available = media.duration - clip.sourceStart
        while clip.sourceDuration > available, clip.duration > Clip.minimumDuration {
            clip.duration = clip.duration - .oneFrame
        }
        timeline.clips[index] = clip
    }
}
