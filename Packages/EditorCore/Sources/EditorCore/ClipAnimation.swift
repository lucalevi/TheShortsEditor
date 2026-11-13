import CoreMedia
import Foundation

// Clip animations: how a clip's picture comes in at its start and goes at its end (fade, pop,
// slide, spin…). The same movements are meant for titles and stickers (Stage H), so they live
// in one enum, `MotionAnimation`, and describe a picture's state, not how it is drawn.

/// A movement a picture can come in or go out with.
public enum MotionAnimation: String, Codable, CaseIterable, Identifiable, Sendable {
    case fade, pop, zoom, slideUp, slideDown, slideLeft, slideRight, spin, blur

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fade: "Fade"
        case .pop: "Pop"
        case .zoom: "Zoom"
        case .slideUp: "Slide Up"
        case .slideDown: "Slide Down"
        case .slideLeft: "Slide Left"
        case .slideRight: "Slide Right"
        case .spin: "Spin"
        case .blur: "Blur"
        }
    }

    public var systemImage: String {
        switch self {
        case .fade: "circle.lefthalf.filled"
        case .pop: "plus.magnifyingglass"
        case .zoom: "arrow.down.right.and.arrow.up.left"
        case .slideUp: "arrow.up"
        case .slideDown: "arrow.down"
        case .slideLeft: "arrow.left"
        case .slideRight: "arrow.right"
        case .spin: "arrow.trianglehead.clockwise"
        case .blur: "drop"
        }
    }

    /// The picture's state `progress` (0…1) through the movement. Coming in, 0 is the first
    /// frame (furthest away) and 1 is in place; going out, 0 is in place and 1 is gone.
    public func state(progress: Double, entering: Bool) -> AnimationState {
        let p = min(max(progress, 0), 1)
        // Coming in slows down into place; going out speeds up away from it.
        let away = entering ? pow(1 - p, 3) : p * p
        var state = AnimationState.identity
        switch self {
        case .fade:
            state.opacity = 1 - away
        case .pop:
            if entering {
                // Grows past its size a little, then settles.
                let c1 = 1.70158, c3 = c1 + 1
                let back = 1 + c3 * pow(p - 1, 3) + c1 * pow(p - 1, 2)
                state.scale = 0.5 + 0.5 * back
                state.opacity = min(1, p * 4)
            } else {
                state.scale = 1 - 0.5 * away
                state.opacity = 1 - away
            }
        case .zoom:
            state.scale = 1 + 0.5 * away
            state.opacity = 1 - away
        case .slideUp:
            state.offsetY = entering ? away : -away
        case .slideDown:
            state.offsetY = entering ? -away : away
        case .slideLeft:
            state.offsetX = entering ? away : -away
        case .slideRight:
            state.offsetX = entering ? -away : away
        case .spin:
            state.rotation = (entering ? -180 : 180) * away
            state.scale = 1 - 0.7 * away
            state.opacity = 1 - away
        case .blur:
            state.blur = 40 * away
            state.opacity = 1 - 0.4 * away
        }
        return state
    }
}

/// How a picture is changed at one moment of an animation, around the middle of where it is drawn.
public struct AnimationState: Equatable, Sendable {
    public var scale = 1.0
    /// Moved by fractions of the width and height of where it is drawn (positive: right, down).
    public var offsetX = 0.0
    public var offsetY = 0.0
    /// Degrees, clockwise.
    public var rotation = 0.0
    public var opacity = 1.0
    /// Blur radius in canvas pixels.
    public var blur = 0.0

    public static let identity = AnimationState()
    public var isIdentity: Bool { self == .identity }
}

/// A clip's way in or out: the movement and how long it takes.
public struct ClipAnimation: Codable, Equatable, Hashable, Sendable {
    public var kind: MotionAnimation
    public var duration: CMTime

    public init(_ kind: MotionAnimation, duration: CMTime = ClipAnimation.defaultDuration) {
        self.kind = kind
        self.duration = duration
    }

    public static let defaultDuration = CMTime(value: 1, timescale: 2)
    public static let durationRange: ClosedRange<Double> = 0.2...2

    private enum CodingKeys: String, CodingKey { case kind, duration }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(MotionAnimation.self, forKey: .kind)
        duration = try c.decodeTime(forKey: .duration)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(time: duration, forKey: .duration)
    }
}

public extension Clip {
    /// How long the way in and the way out really last: each as asked, but together never more
    /// than the clip (they share it in proportion).
    var animationLengths: (in: CMTime, out: CMTime) {
        let wantedIn = animationIn?.duration ?? .zero, wantedOut = animationOut?.duration ?? .zero
        let total = wantedIn + wantedOut
        guard total > duration, total > .zero else { return (wantedIn, wantedOut) }
        let share = duration.seconds / total.seconds
        return (CMTimeMultiplyByFloat64(wantedIn, multiplier: share), CMTimeMultiplyByFloat64(wantedOut, multiplier: share))
    }

    /// The picture's animation state `offset` into the clip, or nil when it is simply in place.
    func animationState(atOffset offset: CMTime) -> AnimationState? {
        guard animationIn != nil || animationOut != nil else { return nil }
        let lengths = animationLengths
        // Measured from the middle of the frame, so the first frame already moves a little.
        let t = offset.seconds + 0.5 / Double(Project.frameRate)
        if let animationIn, lengths.in > .zero, t < lengths.in.seconds {
            return animationIn.kind.state(progress: t / lengths.in.seconds, entering: true)
        }
        let outStart = duration.seconds - lengths.out.seconds
        if let animationOut, lengths.out > .zero, t > outStart {
            return animationOut.kind.state(progress: (t - outStart) / lengths.out.seconds, entering: false)
        }
        return nil
    }
}

public extension Project {
    /// Sets how a clip (main or B-roll) comes in (`entering`) or goes out; nil for none.
    mutating func setAnimation(_ animation: ClipAnimation?, entering: Bool, for id: Clip.ID) {
        guard anyClip(id: id) != nil, sound(id: id) == nil else { return }
        var animation = animation
        if let seconds = animation?.duration.seconds {
            let clamped = min(max(seconds, ClipAnimation.durationRange.lowerBound), ClipAnimation.durationRange.upperBound)
            animation?.duration = CMTime(seconds: clamped, preferredTimescale: 600).snappedToFrame()
        }
        updateAnyClip(id) { clip in
            if entering { clip.animationIn = animation } else { clip.animationOut = animation }
        }
    }
}
