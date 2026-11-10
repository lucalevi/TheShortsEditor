import CoreGraphics
import CoreMedia
import Foundation

/// How the picture of a video file wanders from frame to frame (camera shake), measured once per
/// file. Stabilize then moves each frame by the difference between this wobbly path and a
/// smoothed copy of it, and zooms in just enough to hide the edges that moving uncovers.
///
/// Positions are where the filmed content sits relative to the first frame, as fractions of the
/// picture's width and height in the file's stored orientation, with y going down.
public struct ShakePath: Codable, Equatable, Sendable {
    /// Seconds between two positions (one per frame of the file).
    public var interval: Double
    /// The file time of the first position, in seconds.
    public var start: Double
    public var positions: [CGPoint]

    public init(interval: Double, start: Double = 0, positions: [CGPoint]) {
        self.interval = interval
        self.start = start
        self.positions = positions
    }

    /// The most a clip is zoomed in to hide moved edges; beyond it, some shake is left.
    public static let maxZoom = 1.25

    /// How long the smoothing looks around a moment, in seconds, for a steadiness of 0…1.
    static func window(for steadiness: Double) -> Double { 0.15 + 0.85 * steadiness.clamped(0, 1) }

    /// Where the content is in the frame on screen at `seconds` of the file: the last one that
    /// starts at or before then (a frame stays on screen until the next one).
    public func position(at seconds: Double) -> CGPoint {
        guard !positions.isEmpty, interval > 0 else { return .zero }
        // A little leeway, so a time that is a frame's start up to rounding finds that frame.
        let index = Int(((seconds - start) / interval + 0.01).rounded(.down))
        return positions[min(max(index, 0), positions.count - 1)]
    }

    /// The smoothed path at `seconds`: a Gaussian average around it (a still camera wouldn't move at all).
    public func smoothed(at seconds: Double, steadiness: Double) -> CGPoint {
        guard positions.count > 1, interval > 0 else { return position(at: seconds) }
        let sigma = Self.window(for: steadiness)
        let reach = Int((3 * sigma / interval).rounded(.up))
        let centre = Int(((seconds - start) / interval).rounded())
        var sum = CGPoint.zero, weights = 0.0
        for i in (centre - reach)...(centre + reach) {
            // Past the ends, the end positions are repeated, so the path doesn't drift there.
            let p = positions[min(max(i, 0), positions.count - 1)]
            let d = (start + Double(i) * interval - seconds) / sigma
            let w = exp(-0.5 * d * d)
            sum.x += p.x * w
            sum.y += p.y * w
            weights += w
        }
        return CGPoint(x: sum.x / weights, y: sum.y / weights)
    }

    /// How far to move the frame at `seconds` (fractions of the picture, y down) to put its
    /// content on the smooth path.
    public func correction(at seconds: Double, steadiness: Double) -> CGVector {
        let raw = position(at: seconds), smooth = smoothed(at: seconds, steadiness: steadiness)
        return CGVector(dx: smooth.x - raw.x, dy: smooth.y - raw.y)
    }

    /// How much to zoom in over a stretch of the file so the moved frames still cover the picture,
    /// at most `maxZoom`.
    public func zoom(over range: ClosedRange<Double>, steadiness: Double) -> Double {
        guard positions.count > 1, interval > 0, steadiness > 0 else { return 1 }
        var worst = 0.0
        var t = range.lowerBound
        while t <= range.upperBound {
            let c = correction(at: t, steadiness: steadiness)
            worst = max(worst, abs(c.dx), abs(c.dy))
            t += interval
        }
        // Moving by d of the picture uncovers d on one side: zooming by 1 + 2d around the middle hides it.
        return min(1 + 2 * worst + 0.005, Self.maxZoom)
    }
}

/// What the compositor needs to steady one clip: its file's path, how strongly, and a zoom that
/// stays the same for the whole clip.
public struct Steadying: Sendable, Equatable {
    public let path: ShakePath
    public let steadiness: Double
    public let zoom: Double

    public init(path: ShakePath, clip: Clip) {
        self.path = path
        steadiness = clip.steadiness
        let start = clip.sourceStart.seconds, end = clip.sourceRange.end.seconds
        zoom = path.zoom(over: start...max(start, end), steadiness: clip.steadiness)
    }

    /// The move (as fractions of the picture, y down) and zoom for the frame at `sourceTime`.
    public func adjustment(atSourceTime sourceTime: CMTime) -> (shift: CGVector, zoom: Double) {
        var shift = path.correction(at: sourceTime.seconds, steadiness: steadiness)
        // What is left over after zooming is clamped, so no edge ever shows.
        let room = (zoom - 1) / 2
        shift.dx = shift.dx.clamped(-room, room)
        shift.dy = shift.dy.clamped(-room, room)
        return (shift, zoom)
    }

    /// The same as a transform of the file's picture (stored orientation, top-left origin, pixels).
    public func transform(atSourceTime sourceTime: CMTime, naturalSize: CGSize) -> CGAffineTransform {
        let (shift, zoom) = adjustment(atSourceTime: sourceTime)
        let w = naturalSize.width, h = naturalSize.height
        // Zoomed around the middle first, then moved, so the move is exactly `shift` of the picture.
        return CGAffineTransform(translationX: -w / 2, y: -h / 2)
            .concatenating(CGAffineTransform(scaleX: zoom, y: zoom))
            .concatenating(CGAffineTransform(translationX: w / 2 + shift.dx * w, y: h / 2 + shift.dy * h))
    }
}

extension CGFloat {
    func clamped(_ low: CGFloat, _ high: CGFloat) -> CGFloat { Swift.min(Swift.max(self, low), high) }
}

public extension Clip {
    /// Steadiness 0…1 offered when Stabilize is switched on.
    static let defaultSteadiness = 0.5
}
