import CoreMedia
import Foundation

// Transitions between main clips, see-through B-roll and picture fades.

// MARK: - Transitions

/// How one main clip changes into the next.
public enum TransitionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    /// One picture melts into the other.
    case dissolve
    /// Down to black, then up into the next clip.
    case throughBlack
    /// A white flash between the clips.
    case throughWhite
    /// The next clip pushes the old one out to the left.
    case slide
    /// The next clip pushes the old one up, like swiping to the next Short.
    case slideUp
    /// Rushes into the picture and lands on the next clip.
    case zoom
    /// A fast, blurred push, as if the camera whipped round.
    case whip
    /// The next clip is uncovered from left to right.
    case wipe

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .dissolve: "Dissolve"
        case .throughBlack: "Through Black"
        case .throughWhite: "Flash"
        case .slide: "Slide"
        case .slideUp: "Slide Up"
        case .zoom: "Zoom"
        case .whip: "Whip"
        case .wipe: "Wipe"
        }
    }

    public var hint: String {
        switch self {
        case .dissolve: "One picture melts into the next"
        case .throughBlack: "Goes dark, then the next clip comes up"
        case .throughWhite: "A white flash between the clips"
        case .slide: "The next clip pushes in from the right"
        case .slideUp: "The next clip pushes in from below, like swiping"
        case .zoom: "Rushes in and lands on the next clip"
        case .whip: "A fast blurred push, like a camera whip"
        case .wipe: "The next clip is uncovered from the left"
        }
    }

    public var systemImage: String {
        switch self {
        case .dissolve: "circle.lefthalf.filled"
        case .throughBlack: "moon.fill"
        case .throughWhite: "sun.max.fill"
        case .slide: "arrow.left.square"
        case .slideUp: "arrow.up.square"
        case .zoom: "plus.magnifyingglass"
        case .whip: "wind"
        case .wipe: "rectangle.righthalf.inset.filled"
        }
    }
}

/// A transition between two main clips. It is kept on the clip before the cut
/// (`Clip.transitionOut`), so it stays with the cut when clips are split or moved.
///
/// The Short doesn't change length: the transition plays over the half before the cut and the
/// half after it. In its first half the next clip is already showing through, in its second half
/// the old clip is still going (with more of their files where there is more, else held on their
/// first or last picture).
public struct ClipTransition: Codable, Equatable, Sendable {
    public var kind: TransitionKind
    /// The length asked for. A short clip beside the cut makes it shorter (`Timeline.transitionSpans`).
    public var duration: CMTime

    public static let defaultDuration = CMTime(value: 15, timescale: Project.frameRate)
    public static let minimumDuration = CMTime(value: 6, timescale: Project.frameRate)
    public static let maximumDuration = CMTime(value: 60, timescale: Project.frameRate)

    public init(kind: TransitionKind = .dissolve, duration: CMTime = ClipTransition.defaultDuration) {
        self.kind = kind
        self.duration = Self.allowed(duration)
    }

    /// `duration` on whole frames, an even number of them (half before the cut, half after), in range.
    public static func allowed(_ duration: CMTime) -> CMTime {
        let frames = duration.snappedToFrame().clamped(minimumDuration, maximumDuration).snappedToFrame().value
        return CMTime(value: frames - frames % 2, timescale: Project.frameRate)
    }

    private enum CodingKeys: String, CodingKey { case kind, duration }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(TransitionKind.self, forKey: .kind)
        duration = Self.allowed(try c.decodeTime(forKey: .duration))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(time: duration, forKey: .duration)
    }
}

/// A transition as it plays on the timeline.
public struct TransitionSpan: Equatable, Sendable {
    /// The clip going out and the clip coming in.
    public let from: Clip.ID
    public let to: Clip.ID
    public let kind: TransitionKind
    /// The cut it sits on.
    public let cut: CMTime
    /// When it plays: the same length before and after the cut.
    public let range: CMTimeRange

    public var half: CMTime { cut - range.start }

    /// How far through it is at `time`, 0…1.
    public func progress(at time: CMTime) -> Double {
        guard range.duration > .zero else { return 1 }
        return min(max((time - range.start).seconds / range.duration.seconds, 0), 1)
    }
}

public extension Timeline {
    /// The transitions that play, in order. Each takes at most half of the clips on either side,
    /// so two transitions never meet inside a short clip; one squeezed under two frames is left out.
    var transitionSpans: [TransitionSpan] {
        var spans: [TransitionSpan] = []
        var cut = CMTime.zero
        for (index, clip) in clips.enumerated() {
            cut = cut + clip.duration
            guard let transition = clip.transitionOut, index + 1 < clips.count else { continue }
            let next = clips[index + 1]
            let wanted = ClipTransition.allowed(transition.duration).value / 2
            let room = min(halfFrames(clip.duration), halfFrames(next.duration))
            let frames = min(wanted, room)
            guard frames >= 1 else { continue }
            let half = CMTime(value: frames, timescale: Project.frameRate)
            spans.append(TransitionSpan(from: clip.id, to: next.id, kind: transition.kind, cut: cut,
                                        range: CMTimeRange(start: cut - half, end: cut + half)))
        }
        return spans
    }

    /// The transition playing at `time`, if any.
    func transitionSpan(at time: CMTime) -> TransitionSpan? {
        transitionSpans.first { $0.range.containsTime(time) }
    }

    /// The cuts between clips, as (the clip before the cut, the time).
    var cuts: [(before: Clip.ID, time: CMTime)] {
        var result: [(before: Clip.ID, time: CMTime)] = []
        var time = CMTime.zero
        for clip in clips.dropLast() {
            time = time + clip.duration
            result.append((clip.id, time))
        }
        return result
    }

    /// The clip before the cut nearest `time` (nil with fewer than two clips).
    func clipBeforeCut(nearest time: CMTime) -> Clip.ID? {
        cuts.min { abs(($0.time - time).seconds) < abs(($1.time - time).seconds) }?.before
    }

    /// Whole frames in half of `duration`, rounded down.
    private func halfFrames(_ duration: CMTime) -> Int64 {
        duration.convertScale(Project.frameRate, method: .roundTowardNegativeInfinity).value / 2
    }
}

public extension Project {
    /// The transition after main clip `id`, if it has one and a clip follows it.
    func transition(after id: Clip.ID) -> ClipTransition? {
        guard let index = timeline.index(of: id), index + 1 < timeline.clips.count else { return nil }
        return timeline.clips[index].transitionOut
    }

    /// Puts a transition on the cut after main clip `id` (nil takes it away). False when no clip
    /// follows it.
    @discardableResult
    mutating func setTransition(_ transition: ClipTransition?, after id: Clip.ID) -> Bool {
        guard let index = timeline.index(of: id), index + 1 < timeline.clips.count else { return false }
        timeline.clips[index].transitionOut = transition
        return true
    }

    /// The same transition on every cut (nil removes them all).
    mutating func setTransitionOnEveryCut(_ transition: ClipTransition?) {
        for index in timeline.clips.indices.dropLast() { timeline.clips[index].transitionOut = transition }
        if let last = timeline.clips.indices.last { timeline.clips[last].transitionOut = nil }
    }

    /// How many cuts have a transition.
    var transitionCount: Int {
        timeline.clips.dropLast().filter { $0.transitionOut != nil }.count
    }
}

// MARK: - See-through pictures and picture fades

public extension Clip {
    /// The picture's fades as they are seen: together no longer than the clip.
    var seenPictureFades: (in: CMTime, out: CMTime) {
        let fadeIn = max(pictureFadeIn, .zero), fadeOut = max(pictureFadeOut, .zero)
        let total = fadeIn + fadeOut
        guard total > duration, total > .zero else { return (min(fadeIn, duration), min(fadeOut, duration)) }
        let scale = duration.seconds / total.seconds
        return (CMTime(seconds: fadeIn.seconds * scale, preferredTimescale: 600), CMTime(seconds: fadeOut.seconds * scale, preferredTimescale: 600))
    }

    /// How much of the picture's fades shows at `offset` into the clip: 0 at its very start with a
    /// fade in, 1 once it is fully there. `length` is the clip's length when it is cut short.
    func pictureFade(atOffset offset: CMTime, length: CMTime? = nil) -> Double {
        let fades = seenPictureFades
        let length = length ?? duration
        var fade = 1.0
        // Counted from the middle of each frame, so the first frame already shows a little.
        let seconds = offset.seconds + 0.5 / Double(Project.frameRate)
        if fades.in > .zero { fade = min(fade, seconds / fades.in.seconds) }
        if fades.out > .zero { fade = min(fade, (length.seconds - offset.seconds - 0.5 / Double(Project.frameRate)) / fades.out.seconds) }
        return min(max(fade, 0), 1)
    }

    /// Whether the picture is see-through or fades at some point.
    var hasPictureFades: Bool { pictureFadeIn > .zero || pictureFadeOut > .zero }
}
