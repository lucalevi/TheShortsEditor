import CoreGraphics
import CoreMedia
import Foundation

/// How a B-roll clip shares the screen with the main clip.
public enum OverlayLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Wherever its placement puts it, over the main clip.
    case free
    /// Split screen: it fills the top half, the main clip the bottom half.
    case top
    /// Split screen: it fills the bottom half, the main clip the top half.
    case bottom
    /// Side by side: it fills the left half, the main clip the right half.
    case left
    /// Side by side: it fills the right half, the main clip the left half.
    case right
    /// It fills the top third (a face over gameplay), the main clip the rest.
    case topThird
    /// It fills the bottom third, the main clip the rest.
    case bottomThird

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .free: "Over"
        case .top: "Top Half"
        case .bottom: "Bottom Half"
        case .left: "Left Half"
        case .right: "Right Half"
        case .topThird: "Top Third"
        case .bottomThird: "Bottom Third"
        }
    }

    /// The split layouts, in the order they are offered.
    public static let splits: [OverlayLayout] = [.top, .bottom, .topThird, .bottomThird, .left, .right]

    public var isSplit: Bool { self != .free }

    /// The edge of the screen it takes, and how much of it.
    var split: (edge: SplitEdge, fraction: CGFloat)? {
        switch self {
        case .free: nil
        case .top: (.top, 1 / 2)
        case .bottom: (.bottom, 1 / 2)
        case .left: (.left, 1 / 2)
        case .right: (.right, 1 / 2)
        case .topThird: (.top, 1 / 3)
        case .bottomThird: (.bottom, 1 / 3)
        }
    }
}

enum SplitEdge: CaseIterable {
    case top, bottom, left, right
}

/// The corners a small picture (picture-in-picture) can go in, clear of YouTube's interface.
public enum PictureCorner: String, CaseIterable, Identifiable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .topLeft: "Top Left"
        case .topRight: "Top Right"
        case .bottomLeft: "Bottom Left"
        case .bottomRight: "Bottom Right"
        }
    }
}

public extension Placement {
    /// The transform after framing for a picture drawn inside `region` (canvas pixels, origin at
    /// the top left) instead of the whole canvas.
    func transform(in region: CGRect) -> CGAffineTransform {
        transform(canvas: region.size).concatenating(CGAffineTransform(translationX: region.minX, y: region.minY))
    }

    /// A small picture in `corner`, about two fifths of the screen wide, kept clear of the areas
    /// YouTube covers.
    static func pictureInPicture(_ corner: PictureCorner, displaySize: CGSize, framing: Framing) -> Placement {
        let canvas = Project.canvasSize
        let framed = framing.framedSize(of: displaySize)
        guard framed.width > 0, framed.height > 0 else { return .identity }
        let scale = min(canvas.width * 0.4 / framed.width, canvas.height * 0.36 / framed.height)
        let size = CGSize(width: framed.width * scale, height: framed.height * scale)
        let margin: CGFloat = 36
        let left = margin + size.width / 2
        let right = canvas.width - SafeZone.right - margin / 2 - size.width / 2
        let top = SafeZone.top + margin + size.height / 2
        let bottom = canvas.height - SafeZone.bottom - margin - size.height / 2
        let x = corner == .topLeft || corner == .bottomLeft ? left : right
        let y = corner == .topLeft || corner == .topRight ? top : bottom
        return Placement(offsetX: (x - canvas.width / 2) / canvas.width, offsetY: (y - canvas.height / 2) / canvas.height, scale: scale)
    }
}

public extension Framing {
    /// The transform that places a picture inside `region` of the canvas.
    func transform(naturalSize: CGSize, preferredTransform: CGAffineTransform, region: CGRect) -> CGAffineTransform {
        transform(naturalSize: naturalSize, preferredTransform: preferredTransform, canvas: region.size)
            .concatenating(CGAffineTransform(translationX: region.minX, y: region.minY))
    }

    /// Where a picture ends up when drawn inside `region`.
    func placedFrame(of displaySize: CGSize, placement: Placement, region: CGRect) -> PlacedFrame {
        var frame = placedFrame(of: displaySize, placement: placement, canvas: region.size)
        frame.center.x += region.minX
        frame.center.y += region.minY
        return frame
    }
}

public extension PlacedFrame {
    /// Whether the picture covers all of `region`.
    func covers(_ region: CGRect) -> Bool {
        var local = self
        local.center.x -= region.minX
        local.center.y -= region.minY
        return local.covers(region.size)
    }
}

/// Where each picture on screen is drawn at one moment.
public struct ScreenRegions: Equatable, Sendable {
    public var main: CGRect
    public var overlays: [Clip.ID: CGRect]

    public func region(for clipID: Clip.ID, isMain: Bool) -> CGRect {
        isMain ? main : overlays[clipID] ?? CGRect(origin: .zero, size: Project.canvasSize)
    }
}

public extension Project {
    /// Where the main clip and the B-roll on screen at `time` are drawn: the whole canvas, or
    /// the parts of a split screen. Each B-roll with a split layout takes its edge of the screen
    /// (top and bottom strips across the whole width, left and right ones between them) and the
    /// main clip gets the rest, so a top third and a bottom third leave it the middle. When two
    /// want the same edge, or the main clip would keep less than a quarter, the topmost wins and
    /// the other is drawn over everything.
    func regions(at time: CMTime) -> ScreenRegions {
        let size = Project.canvasSize
        var regions = ScreenRegions(main: CGRect(origin: .zero, size: size), overlays: [:])
        var claims: [SplitEdge: (id: Clip.ID, fraction: CGFloat)] = [:]
        for overlay in overlaysOnScreen(at: time).reversed() {
            guard let split = overlay.layout.split, claims[split.edge] == nil else { continue }
            let opposite: SplitEdge =
                switch split.edge {
                case .top: .bottom
                case .bottom: .top
                case .left: .right
                case .right: .left
                }
            guard split.fraction + (claims[opposite]?.fraction ?? 0) <= 0.75 else { continue }
            claims[split.edge] = (overlay.id, split.fraction)
        }
        let top = (claims[.top]?.fraction ?? 0) * size.height
        let bottom = (claims[.bottom]?.fraction ?? 0) * size.height
        let left = (claims[.left]?.fraction ?? 0) * size.width
        let right = (claims[.right]?.fraction ?? 0) * size.width
        let middle = size.height - top - bottom
        if let id = claims[.top]?.id { regions.overlays[id] = CGRect(x: 0, y: 0, width: size.width, height: top) }
        if let id = claims[.bottom]?.id { regions.overlays[id] = CGRect(x: 0, y: size.height - bottom, width: size.width, height: bottom) }
        if let id = claims[.left]?.id { regions.overlays[id] = CGRect(x: 0, y: top, width: left, height: middle) }
        if let id = claims[.right]?.id { regions.overlays[id] = CGRect(x: size.width - right, y: top, width: right, height: middle) }
        regions.main = CGRect(x: left, y: top, width: size.width - left - right, height: middle)
        return regions
    }
}

// MARK: - Following the subject

/// Turns where the subject is in each sampled frame into keyframes that keep it in the middle of
/// a vertical Short ("auto reframe"): smoothed so the picture glides instead of jittering.
public enum Reframe {
    /// The subject's middle across the picture (0 left … 1 right) at a time in the source.
    public struct Sample: Equatable, Sendable {
        public var time: CMTime
        public var x: Double

        public init(time: CMTime, x: Double) {
            self.time = time
            self.x = x
        }
    }

    /// How far to look either side when smoothing.
    static let smoothing = 0.8
    /// Keyframes are at least this far apart.
    static let spacing = CMTime(value: 1, timescale: 2)

    /// Keyframes (fill screen) for `clip` showing a picture of `displaySize` that follow `samples`.
    /// Empty when the picture already fits across the screen (nothing to follow).
    public static func keyframes(for clip: Clip, displaySize: CGSize, samples: [Sample]) -> [Keyframe] {
        let canvas = Project.canvasSize
        let width = Framing.fill.framedSize(of: displaySize).width
        let room = (width - canvas.width) / 2 / canvas.width
        guard room > 0.001, !samples.isEmpty else { return [] }
        let sorted = samples.sorted { $0.time < $1.time }

        func smoothed(at time: CMTime) -> Double {
            let near = sorted.filter { abs(($0.time - time).seconds) <= smoothing }
            let values = near.isEmpty ? [sorted.min { abs(($0.time - time).seconds) < abs(($1.time - time).seconds) }!.x] : near.map(\.x)
            return values.reduce(0, +) / Double(values.count)
        }
        func offset(_ x: Double) -> Double { min(max(-(x - 0.5) * width / canvas.width, -room), room) }

        var times: [CMTime] = []
        var t = clip.sourceStart
        while t < clip.sourceRange.end {
            times.append(t.snappedToFrame())
            t = t + spacing
        }
        times.append((clip.sourceRange.end - .oneFrame).snappedToFrame())
        var frames = times.map { time in
            Keyframe(time: time, placement: Placement(offsetX: offset(smoothed(at: time)), scale: clip.placement.scale), easing: .smooth)
        }
        // Leave out keyframes the picture would pass through anyway, so it moves calmly.
        var index = 1
        while index < frames.count - 1 {
            let a = frames[index - 1], b = frames[index], c = frames[index + 1]
            let fraction = (b.time - a.time).seconds / max((c.time - a.time).seconds, 0.001)
            let expected = a.placement.offsetX + (c.placement.offsetX - a.placement.offsetX) * fraction
            if abs(expected - b.placement.offsetX) < 0.015 {
                frames.remove(at: index)
            } else {
                index += 1
            }
        }
        if frames.count == 2, abs(frames[0].placement.offsetX - frames[1].placement.offsetX) < 0.015 {
            return [frames[0]]
        }
        return frames
    }
}
