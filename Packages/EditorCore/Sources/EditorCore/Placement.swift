import CoreGraphics
import CoreMedia
import Foundation

/// Where a clip's picture sits on the canvas, on top of its framing (Fill screen / Show all):
/// moved from the centre, made bigger or smaller, turned.
///
/// The identity placement leaves the framing as it is. A "punch-in" is just a bigger scale.
public struct Placement: Codable, Equatable, Hashable, Sendable {
    /// How far the middle of the picture is from the middle of the canvas, as a fraction of the
    /// canvas width (positive is to the right).
    public var offsetX: Double
    /// The same, as a fraction of the canvas height (positive is down).
    public var offsetY: Double
    /// 1 is the size the framing gives; 1.2 is 20% bigger.
    public var scale: Double
    /// Degrees, clockwise.
    public var rotation: Double
    /// How solid the picture is: 1 hides what is behind it, 0 can't be seen at all.
    public var opacity: Double

    public init(offsetX: Double = 0, offsetY: Double = 0, scale: Double = 1, rotation: Double = 0, opacity: Double = 1) {
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.scale = scale
        self.rotation = rotation
        self.opacity = opacity
    }

    private enum CodingKeys: String, CodingKey { case offsetX, offsetY, scale, rotation, opacity }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        offsetX = try c.decode(Double.self, forKey: .offsetX)
        offsetY = try c.decode(Double.self, forKey: .offsetY)
        scale = try c.decode(Double.self, forKey: .scale)
        rotation = try c.decode(Double.self, forKey: .rotation)
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(offsetX, forKey: .offsetX)
        try c.encode(offsetY, forKey: .offsetY)
        try c.encode(scale, forKey: .scale)
        try c.encode(rotation, forKey: .rotation)
        if opacity != 1 { try c.encode(opacity, forKey: .opacity) }
    }

    public static let identity = Placement()
    /// The smallest and biggest a picture can be made.
    public static let scaleRange: ClosedRange<Double> = 0.1...5
    /// The zoom used for a punch-in: enough to hide a jump cut, not so much the picture gets soft.
    public static let punchInScale = 1.2

    public var isIdentity: Bool { self == .identity }

    /// The same placement with the scale kept in range and the rotation in -180…180.
    public var normalized: Placement {
        var p = self
        p.scale = min(max(p.scale, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
        p.rotation = p.rotation.truncatingRemainder(dividingBy: 360)
        if p.rotation > 180 { p.rotation -= 360 }
        if p.rotation < -180 { p.rotation += 360 }
        p.opacity = min(max(p.opacity, 0), 1)
        return p
    }

    /// The transform applied after the framing, in canvas coordinates with the origin at the top
    /// left: scale and turn around the middle of the canvas, then move.
    public func transform(canvas: CGSize = Project.canvasSize) -> CGAffineTransform {
        let cx = canvas.width / 2, cy = canvas.height / 2
        return CGAffineTransform(translationX: -cx, y: -cy)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(rotationAngle: rotation * .pi / 180))
            .concatenating(CGAffineTransform(translationX: cx + offsetX * canvas.width, y: cy + offsetY * canvas.height))
    }

    /// The placement a `fraction` of the way from `self` to `other`. Size changes evenly in
    /// proportion (a zoom from 1 to 2 is at 1.41 half way), which looks steady to the eye.
    public func interpolated(to other: Placement, fraction: Double) -> Placement {
        let f = min(max(fraction, 0), 1)
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * f }
        let scale = self.scale > 0 && other.scale > 0 ? exp(mix(log(self.scale), log(other.scale))) : mix(self.scale, other.scale)
        return Placement(offsetX: mix(offsetX, other.offsetX), offsetY: mix(offsetY, other.offsetY), scale: scale, rotation: mix(rotation, other.rotation),
                         opacity: mix(opacity, other.opacity))
    }
}

/// Where a clip's picture ends up on the canvas: its middle, its size and how much it is turned.
/// The same as the rendered picture, for drawing handles in the viewer.
public struct PlacedFrame: Equatable, Sendable {
    /// Canvas pixels, origin at the top left.
    public var center: CGPoint
    public var size: CGSize
    /// Degrees, clockwise.
    public var rotation: Double

    /// Whether the picture covers the whole canvas, so nothing behind it can be seen.
    public func covers(_ canvas: CGSize = Project.canvasSize) -> Bool {
        let corners = [CGPoint.zero, CGPoint(x: canvas.width, y: 0), CGPoint(x: 0, y: canvas.height), CGPoint(x: canvas.width, y: canvas.height)]
        let angle = -rotation * .pi / 180
        return corners.allSatisfy { corner in
            // The canvas corner in the picture's own (unturned) frame.
            let dx = corner.x - center.x, dy = corner.y - center.y
            let x = dx * cos(angle) - dy * sin(angle), y = dx * sin(angle) + dy * cos(angle)
            return abs(x) <= size.width / 2 + 0.5 && abs(y) <= size.height / 2 + 0.5
        }
    }
}

public extension Framing {
    /// The size of a picture of `displaySize` after framing, before any placement.
    func framedSize(of displaySize: CGSize, canvas: CGSize = Project.canvasSize) -> CGSize {
        guard displaySize.width > 0, displaySize.height > 0 else { return canvas }
        let scaleX = canvas.width / displaySize.width, scaleY = canvas.height / displaySize.height
        let scale = self == .fill ? max(scaleX, scaleY) : min(scaleX, scaleY)
        return CGSize(width: displaySize.width * scale, height: displaySize.height * scale)
    }

    /// Where a picture of `displaySize` ends up with this framing and `placement`.
    func placedFrame(of displaySize: CGSize, placement: Placement, canvas: CGSize = Project.canvasSize) -> PlacedFrame {
        let size = framedSize(of: displaySize, canvas: canvas)
        return PlacedFrame(
            center: CGPoint(x: canvas.width / 2 + placement.offsetX * canvas.width, y: canvas.height / 2 + placement.offsetY * canvas.height),
            size: CGSize(width: size.width * placement.scale, height: size.height * placement.scale),
            rotation: placement.rotation
        )
    }
}

/// What fills the canvas around a picture that doesn't cover it (Show all, or made smaller).
public enum ClipBackground: String, Codable, CaseIterable, Identifiable, Sendable {
    /// A blurred, enlarged copy of the same picture: the usual look for horizontal footage in a Short.
    case blur
    case black

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .blur: "Blurred"
        case .black: "Black"
        }
    }
}

/// How the picture moves into a keyframe from the one before.
public enum Easing: String, Codable, CaseIterable, Sendable {
    /// Starts and ends gently.
    case smooth
    /// At a steady pace, like a slow zoom.
    case linear

    func apply(_ t: Double) -> Double {
        switch self {
        case .linear: t
        case .smooth: t * t * (3 - 2 * t)
        }
    }
}

/// A placement the picture has at one moment. Between keyframes it moves from one to the next.
///
/// The time is in the source file's own time (like caption words), so the motion stays with the
/// footage when the clip is split, trimmed or has pauses removed.
public struct Keyframe: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var time: CMTime
    public var placement: Placement
    public var easing: Easing

    public init(id: UUID = UUID(), time: CMTime, placement: Placement, easing: Easing = .smooth) {
        self.id = id
        self.time = time
        self.placement = placement
        self.easing = easing
    }

    private enum CodingKeys: String, CodingKey { case id, time, placement, easing }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        time = try c.decodeTime(forKey: .time)
        placement = try c.decode(Placement.self, forKey: .placement)
        easing = try c.decodeIfPresent(Easing.self, forKey: .easing) ?? .smooth
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(time: time, forKey: .time)
        try c.encode(placement, forKey: .placement)
        try c.encode(easing, forKey: .easing)
    }
}

/// One-click motions: they write the keyframes for the whole clip.
public enum MotionPreset: String, CaseIterable, Identifiable, Sendable {
    /// Slowly closer over the whole clip.
    case slowZoomIn
    /// Slowly further over the whole clip.
    case slowZoomOut
    /// The picture glides to the left (the view moves right).
    case panLeft
    case panRight
    /// A quick zoom in at the playhead, then it stays close: for a key word or a punchline.
    case zoomAtPlayhead

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .slowZoomIn: "Slow Zoom In"
        case .slowZoomOut: "Slow Zoom Out"
        case .panLeft: "Glide Left"
        case .panRight: "Glide Right"
        case .zoomAtPlayhead: "Zoom In at Playhead"
        }
    }

    public var systemImage: String {
        switch self {
        case .slowZoomIn: "plus.magnifyingglass"
        case .slowZoomOut: "minus.magnifyingglass"
        case .panLeft: "arrow.left"
        case .panRight: "arrow.right"
        case .zoomAtPlayhead: "scope"
        }
    }

    /// How much closer the slow zooms get.
    static let slowZoom = 1.15
    /// How close a zoom at the playhead gets, and how quickly.
    static let quickZoom = 1.3
    static let quickZoomLength = CMTime(value: 8, timescale: Project.frameRate)
}

public extension Clip {
    /// Whether the picture moves over time.
    var hasMotion: Bool { !keyframes.isEmpty }

    /// The placement at `sourceTime` (a time in the source file): the keyframes' motion, or the
    /// clip's fixed placement when it has none. Before the first and after the last keyframe it holds.
    func placement(atSourceTime sourceTime: CMTime) -> Placement {
        guard let first = keyframes.first, let last = keyframes.last else { return placement }
        if sourceTime <= first.time { return first.placement }
        if sourceTime >= last.time { return last.placement }
        for (a, b) in zip(keyframes, keyframes.dropFirst()) where sourceTime < b.time {
            let span = (b.time - a.time).seconds
            let fraction = span > 0 ? (sourceTime - a.time).seconds / span : 1
            return a.placement.interpolated(to: b.placement, fraction: b.easing.apply(fraction))
        }
        return last.placement
    }

    /// Sets the placement at `sourceTime`. Without keyframes it is the clip's fixed placement; with
    /// them, the keyframe at that time is changed (or one is added there).
    mutating func setPlacement(_ newValue: Placement, atSourceTime sourceTime: CMTime) {
        let newValue = newValue.normalized
        guard hasMotion else {
            placement = newValue
            return
        }
        addKeyframe(at: sourceTime, placement: newValue)
    }

    /// Adds a keyframe at `sourceTime` (snapped to a frame) with `placement`, or the placement the
    /// clip has there now. A keyframe already within half a frame of it is changed instead.
    mutating func addKeyframe(at sourceTime: CMTime, placement: Placement? = nil) {
        let time = sourceTime.snappedToFrame()
        let value = (placement ?? self.placement(atSourceTime: time)).normalized
        if let index = keyframes.firstIndex(where: { abs(($0.time - time).seconds) < 0.5 / Double(Project.frameRate) }) {
            keyframes[index].placement = value
        } else {
            keyframes.append(Keyframe(time: time, placement: value))
            keyframes.sort { $0.time < $1.time }
        }
    }

    mutating func removeKeyframe(_ id: Keyframe.ID) {
        guard let index = keyframes.firstIndex(where: { $0.id == id }) else { return }
        let removed = keyframes.remove(at: index)
        // The last one gone: the picture stays where that keyframe had it.
        if keyframes.isEmpty { placement = removed.placement }
    }

    /// Stops the motion, keeping the picture as it is at `sourceTime`.
    mutating func removeMotion(keepingPlacementAt sourceTime: CMTime) {
        placement = placement(atSourceTime: sourceTime)
        keyframes = []
    }

    /// The keyframes inside this clip's part of the source.
    var visibleKeyframes: [Keyframe] {
        keyframes.filter { $0.time >= sourceStart && $0.time <= sourceRange.end }
    }

    /// Replaces the motion with a preset, starting from the placement at `playheadSource` (a time
    /// in the source; it is also where a zoom at the playhead happens).
    mutating func applyMotion(_ preset: MotionPreset, playheadSource: CMTime) {
        let start = sourceStart, end = (sourceRange.end - .oneFrame).snappedToFrame()
        let base = placement(atSourceTime: playheadSource)
        func scaled(_ factor: Double) -> Placement {
            var p = base
            p.scale = base.scale * factor
            return p.normalized
        }
        switch preset {
        case .slowZoomIn:
            keyframes = [Keyframe(time: start, placement: base, easing: .linear), Keyframe(time: end, placement: scaled(MotionPreset.slowZoom), easing: .linear)]
        case .slowZoomOut:
            keyframes = [Keyframe(time: start, placement: scaled(MotionPreset.slowZoom), easing: .linear), Keyframe(time: end, placement: base, easing: .linear)]
        case .panLeft, .panRight:
            // Big enough that the edges never show, then slide across most of the spare width.
            var from = base
            from.scale = max(base.scale, 1.2)
            let room = (from.scale - 1) / 2 * 0.8
            var to = from
            from.offsetX = base.offsetX + (preset == .panLeft ? room : -room)
            to.offsetX = base.offsetX + (preset == .panLeft ? -room : room)
            keyframes = [Keyframe(time: start, placement: from, easing: .linear), Keyframe(time: end, placement: to, easing: .linear)]
        case .zoomAtPlayhead:
            var at = playheadSource.snappedToFrame().clamped(start, end)
            if end - at < MotionPreset.quickZoomLength { at = max(start, end - MotionPreset.quickZoomLength) }
            let done = min(at + MotionPreset.quickZoomLength, end)
            keyframes = [Keyframe(time: at, placement: base), Keyframe(time: done, placement: scaled(MotionPreset.quickZoom))]
        }
        if keyframes.count == 2, keyframes[0].time >= keyframes[1].time {
            // A clip too short for motion: just show the end result.
            placement = keyframes[1].placement
            keyframes = []
        }
    }
}

public extension Project {
    /// Zooms in on every other clip of the same recording, so jump cuts between them look like a
    /// change of camera. Applies to `clipIDs` in timeline order (all clips when nil). A clip from a
    /// different file starts again without zoom. Clips that move (keyframes) are left alone.
    mutating func punchInOnAlternateCuts(_ clipIDs: Set<Clip.ID>? = nil) {
        var previousAsset: MediaAsset.ID?
        var zoomed = false
        for index in timeline.clips.indices {
            let clip = timeline.clips[index]
            guard clipIDs?.contains(clip.id) ?? true else {
                previousAsset = nil
                continue
            }
            zoomed = previousAsset == clip.assetID ? !zoomed : false
            previousAsset = clip.assetID
            guard !clip.hasMotion else { continue }
            timeline.clips[index].placement.scale = zoomed ? Placement.punchInScale : 1
        }
    }
}
