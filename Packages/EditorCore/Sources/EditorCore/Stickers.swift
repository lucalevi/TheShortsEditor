import CoreMedia
import Foundation

// Stage H: stickers, title loops and exits, following something in the video, and ready-made
// text templates. A sticker is a kind of title (`TextOverlay.sticker`): it is timed, selected,
// dragged, animated and follows its clip exactly like one, but draws an emoji or a symbol.

// MARK: - Stickers

/// An emoji or a symbol (SF Symbols) shown over the video.
public struct Sticker: Codable, Equatable, Hashable, Sendable {
    public enum Kind: Codable, Equatable, Hashable, Sendable {
        case emoji(String)
        /// An SF Symbol name, drawn in `Sticker.color`.
        case symbol(String)
    }

    public var kind: Kind
    /// The symbol's colour (emoji have their own).
    public var color: RGBA
    /// The longest side in canvas pixels.
    public var size: Double

    public init(_ kind: Kind, color: RGBA = .white, size: Double = Sticker.defaultSize) {
        self.kind = kind
        self.color = color
        self.size = size
    }

    public static let defaultSize = 260.0
    public static let sizeRange: ClosedRange<Double> = 80...900

    public var isEmoji: Bool { if case .emoji = kind { true } else { false } }

    /// What it is called (on the timeline and in menus).
    public var name: String {
        switch kind {
        case .emoji(let emoji): emoji
        case .symbol(let name): StickerCatalog.symbols.first { $0.name == name }?.displayName ?? name
        }
    }
}

/// The stickers offered: a curated set, made of emoji and the Mac's own symbols.
public enum StickerCatalog {
    public static let emoji: [String] = [
        "🔥", "😂", "😮", "😍", "🤯", "😱", "🤔", "👀", "❤️", "👍", "👇", "👉",
        "👏", "🙌", "💯", "✨", "🎉", "💡", "✅", "❌", "⭐", "🚀", "💰", "⚡",
    ]

    public struct Symbol: Identifiable, Sendable {
        public let name: String
        public let displayName: String
        public var id: String { name }
    }

    public struct Group: Identifiable, Sendable {
        public let name: String
        public let symbols: [Symbol]
        public var id: String { name }
    }

    public static let groups: [Group] = [
        Group(name: "Arrows", symbols: [
            Symbol(name: "arrow.down", displayName: "Arrow Down"),
            Symbol(name: "arrow.up", displayName: "Arrow Up"),
            Symbol(name: "arrow.left", displayName: "Arrow Left"),
            Symbol(name: "arrow.right", displayName: "Arrow Right"),
            Symbol(name: "arrow.turn.right.down", displayName: "Curved Arrow"),
            Symbol(name: "arrowshape.down.fill", displayName: "Big Arrow"),
            Symbol(name: "hand.point.down.fill", displayName: "Pointing Hand"),
            Symbol(name: "hand.tap.fill", displayName: "Tap"),
        ]),
        Group(name: "Shapes", symbols: [
            Symbol(name: "circle", displayName: "Ring"),
            Symbol(name: "square", displayName: "Frame"),
            Symbol(name: "circle.fill", displayName: "Dot"),
            Symbol(name: "star.fill", displayName: "Star"),
            Symbol(name: "heart.fill", displayName: "Heart"),
            Symbol(name: "bolt.fill", displayName: "Lightning"),
            Symbol(name: "sparkles", displayName: "Sparkles"),
            Symbol(name: "flame.fill", displayName: "Flame"),
        ]),
        Group(name: "Signs", symbols: [
            Symbol(name: "bell.fill", displayName: "Bell"),
            Symbol(name: "hand.thumbsup.fill", displayName: "Thumbs Up"),
            Symbol(name: "checkmark.circle.fill", displayName: "Tick"),
            Symbol(name: "xmark.circle.fill", displayName: "Cross"),
            Symbol(name: "exclamationmark.triangle.fill", displayName: "Warning"),
            Symbol(name: "questionmark.circle.fill", displayName: "Question"),
            Symbol(name: "play.rectangle.fill", displayName: "Play Button"),
            Symbol(name: "link", displayName: "Link"),
        ]),
    ]

    public static var symbols: [Symbol] { groups.flatMap(\.symbols) }
}

// MARK: - Loops

/// A movement a title or sticker repeats while it is on screen.
public enum TitleLoop: String, Codable, CaseIterable, Identifiable, Sendable {
    case pulse, float, wiggle, swing, blink, spin, heartbeat

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .pulse: "Pulse"
        case .float: "Float"
        case .wiggle: "Wiggle"
        case .swing: "Swing"
        case .blink: "Blink"
        case .spin: "Spin"
        case .heartbeat: "Heartbeat"
        }
    }

    /// The state `seconds` after it appeared (moves are in canvas pixels for titles: `offsetY`
    /// here is a fraction of the canvas height).
    public func state(seconds t: Double) -> AnimationState {
        var state = AnimationState.identity
        let tau = 2 * Double.pi
        switch self {
        case .pulse:
            let wave: Double = sin(tau * t / 0.9)
            state.scale = 1 + 0.06 * wave
        case .float: state.offsetY = -0.008 * sin(tau * t / 1.4)
        case .wiggle: state.rotation = 6 * sin(tau * t / 0.5)
        case .swing: state.rotation = 12 * sin(tau * t / 1.6)
        case .blink:
            let wave: Double = cos(tau * t / 0.8)
            state.opacity = 0.35 + 0.65 * (0.5 + 0.5 * wave)
        case .spin: state.rotation = 360 * (t / 2).truncatingRemainder(dividingBy: 1)
        case .heartbeat:
            // Two quick beats, then a rest.
            let phase = t.truncatingRemainder(dividingBy: 1.1)
            let beat = { (centre: Double) in exp(-pow((phase - centre) / 0.06, 2)) }
            state.scale = 1 + 0.12 * max(beat(0.1), beat(0.32))
        }
        return state
    }
}

public extension TextOverlay {
    /// How long a title takes to leave by default.
    static let exitDuration = CMTime(value: 2, timescale: 5)

    /// The exit's and the loop's effect `offset` into the title (on top of its entrance, which the
    /// renderer draws). Moves are fractions of the canvas. Nil when neither applies.
    func motionState(atOffset offset: CMTime) -> AnimationState? {
        var state = loop?.state(seconds: offset.seconds)
        if let exit {
            let length = min(exit.duration, CMTimeMultiplyByRatio(duration, multiplier: 1, divisor: 2))
            let t = offset.seconds + 0.5 / Double(Project.frameRate)
            let startsAt = duration.seconds - length.seconds
            if length > .zero, t > startsAt {
                let leaving = exit.kind.state(progress: (t - startsAt) / length.seconds, entering: false)
                var combined = state ?? .identity
                combined.scale *= leaving.scale
                combined.offsetX += leaving.offsetX
                combined.offsetY += leaving.offsetY
                combined.rotation += leaving.rotation
                combined.opacity *= leaving.opacity
                combined.blur = max(combined.blur, leaving.blur)
                state = combined
            }
        }
        return state
    }
}

// MARK: - Following something in the video

/// Where the thing a title or sticker follows was, `offset` after the title appears, as a
/// fraction of the canvas (0…1 across and down).
public struct TrackPoint: Codable, Equatable, Hashable, Sendable {
    public var offset: CMTime
    public var x: Double
    public var y: Double

    public init(offset: CMTime, x: Double, y: Double) {
        self.offset = offset
        self.x = x
        self.y = y
    }

    private enum CodingKeys: String, CodingKey { case offset, x, y }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        offset = try c.decodeTime(forKey: .offset)
        x = try c.decode(Double.self, forKey: .x)
        y = try c.decode(Double.self, forKey: .y)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(time: offset, forKey: .offset)
        try c.encode(x, forKey: .x)
        try c.encode(y, forKey: .y)
    }
}

public extension TextOverlay {
    /// How far (fractions of the canvas) what it follows has moved since it appeared, `offset` in;
    /// straight lines between the measured points, held after the last.
    func trackShift(atOffset offset: CMTime) -> (x: Double, y: Double) {
        guard let track, let first = track.first else { return (0, 0) }
        let t = offset.seconds
        guard let after = track.firstIndex(where: { $0.offset.seconds >= t }) else {
            let last = track[track.count - 1]
            return (last.x - first.x, last.y - first.y)
        }
        guard after > 0 else { return (track[0].x - first.x, track[0].y - first.y) }
        let a = track[after - 1], b = track[after]
        let span = (b.offset - a.offset).seconds
        let f = span > 0 ? (t - a.offset.seconds) / span : 1
        return (a.x + (b.x - a.x) * f - first.x, a.y + (b.y - a.y) * f - first.y)
    }

    /// Where its middle is `offset` in (fractions of the canvas), following what it tracks.
    func position(atOffset offset: CMTime) -> (x: Double, y: Double) {
        let shift = trackShift(atOffset: offset)
        return (horizontalPosition + shift.x, verticalPosition + shift.y)
    }

    var isSticker: Bool { sticker != nil }
}

// MARK: - Adding stickers and templates

public extension Project {
    static let stickerDuration = CMTime(value: 2, timescale: 1)

    /// Adds a sticker at `time` (the playhead), in the middle of the screen, popping in. Returns its id.
    @discardableResult
    mutating func addSticker(_ sticker: Sticker, at time: CMTime, x: Double = 0.5, y: Double = 0.45) -> TextOverlay.ID {
        let length = duration > .zero ? duration : Self.stickerDuration
        let wanted = min(Self.stickerDuration, length)
        var start = time.snappedToFrame().clamped(.zero, length)
        if length - start < wanted { start = max(.zero, length - wanted) }
        var item = TextOverlay(text: sticker.name, style: .simple, entrance: .pop, start: start.snappedToFrame(),
                               duration: wanted.snappedToFrame(), verticalPosition: y, horizontalPosition: x)
        item.sticker = sticker
        titles.append(item)
        return item.id
    }
}

/// Ready-made texts for the moments every Short has: a hook, asking to subscribe, "Part 2"…
/// Each adds one or two titles and stickers, designed together.
public enum TextTemplate: String, CaseIterable, Identifiable, Sendable {
    case hook, subscribe, partTwo, topNumber, question, linkInDescription

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .hook: "Hook"
        case .subscribe: "Subscribe"
        case .partTwo: "Part 2"
        case .topNumber: "Top 3 Number"
        case .question: "Question"
        case .linkInDescription: "Link in Description"
        }
    }

    public var hint: String {
        switch self {
        case .hook: "Big words at the top that make people stay"
        case .subscribe: "A red button and a ringing bell"
        case .partTwo: "For a series: “Part 2” that pops"
        case .topNumber: "A big number and what it is, for countdowns"
        case .question: "A question at the top, with a thinking face"
        case .linkInDescription: "Points down to the description"
        }
    }

    /// The items it adds, timed from 0 (all as long as the template).
    public func items() -> [TextOverlay] {
        let length = CMTime(value: 3, timescale: 1)
        func title(_ text: String, _ style: TitleStyle, y: Double, x: Double = 0.5, size: Double? = nil, entrance: TitleEntrance = .pop,
                   exit: MotionAnimation? = .fade, loop: TitleLoop? = nil) -> TextOverlay {
            var item = TextOverlay(text: text, style: style, entrance: entrance, start: .zero, duration: length, verticalPosition: y, horizontalPosition: x)
            if let size { item.look.size = size }
            item.exit = exit.map { ClipAnimation($0, duration: TextOverlay.exitDuration) }
            item.loop = loop
            return item
        }
        func sticker(_ kind: Sticker.Kind, color: RGBA = .white, size: Double = 200, x: Double, y: Double, loop: TitleLoop?) -> TextOverlay {
            var item = TextOverlay(text: Sticker(kind).name, style: .simple, entrance: .pop, start: .zero, duration: length, verticalPosition: y, horizontalPosition: x)
            item.sticker = Sticker(kind, color: color, size: size)
            item.exit = ClipAnimation(.fade, duration: TextOverlay.exitDuration)
            item.loop = loop
            return item
        }
        switch self {
        case .hook:
            return [title("Wait for it…", .comic, y: 0.24, size: 110, loop: .pulse)]
        case .subscribe:
            return [
                title("Subscribe", .pill, y: 0.62, x: 0.45, size: 80, entrance: .slideUp, exit: .slideDown),
                sticker(.symbol("bell.fill"), color: .yellow, size: 150, x: 0.75, y: 0.62, loop: .wiggle),
            ]
        case .partTwo:
            return [title("Part 2", .popShadow, y: 0.3, size: 150, entrance: .zoom, loop: .pulse)]
        case .topNumber:
            return [
                title("#3", .comic, y: 0.24, size: 200, entrance: .zoom, exit: .zoom),
                title("Your item", .label, y: 0.36, size: 72, entrance: .slideUp),
            ]
        case .question:
            return [
                title("Did you know?", .label, y: 0.24, size: 84),
                sticker(.emoji("🤔"), size: 170, x: 0.5, y: 0.36, loop: .swing),
            ]
        case .linkInDescription:
            return [
                title("Link in description", .dark, y: 0.6, size: 66, entrance: .fade),
                sticker(.symbol("arrow.down"), size: 140, x: 0.5, y: 0.7, loop: .float),
            ]
        }
    }
}

public extension Project {
    /// Adds a text template at `time` (the playhead); near the end it starts earlier so it is
    /// seen whole. Returns the ids of what it added, the main text first.
    @discardableResult
    mutating func addTextTemplate(_ template: TextTemplate, at time: CMTime) -> [TextOverlay.ID] {
        let items = template.items()
        guard let length = items.map(\.duration).max() else { return [] }
        let total = duration > .zero ? duration : length
        let wanted = min(length, total)
        var start = time.snappedToFrame().clamped(.zero, total)
        if total - start < wanted { start = max(.zero, total - wanted) }
        var ids: [TextOverlay.ID] = []
        for var item in items {
            item = TextOverlay(copying: item, start: start.snappedToFrame(), duration: min(item.duration, wanted).snappedToFrame())
            titles.append(item)
            ids.append(item.id)
        }
        return ids
    }

    /// Sets (or clears, with nil) the path a title or sticker follows.
    mutating func setTrack(_ track: [TrackPoint]?, for id: TextOverlay.ID) {
        updateTitle(id) { $0.track = track?.isEmpty == true ? nil : track }
    }
}

extension TextOverlay {
    /// The same item with a new id, start and length.
    init(copying other: TextOverlay, start: CMTime, duration: CMTime) {
        self = TextOverlay(id: UUID(), text: other.text, style: other.style, look: other.look, entrance: other.entrance,
                           start: start, duration: duration, verticalPosition: other.verticalPosition, horizontalPosition: other.horizontalPosition)
        followsClip = other.followsClip
        exit = other.exit
        loop = other.loop
        rotation = other.rotation
        sticker = other.sticker
        track = other.track
    }
}

// MARK: - Following by matching a patch

/// A picture in shades of grey, for following something from frame to frame.
public struct GrayFrame: Sendable {
    public let width: Int
    public let height: Int
    /// Row by row from the top, 0…255.
    public var pixels: [Float]

    public init(width: Int, height: Int, pixels: [Float]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    func value(_ x: Int, _ y: Int) -> Float {
        pixels[min(max(y, 0), height - 1) * width + min(max(x, 0), width - 1)]
    }
}

/// Follows a square patch of a picture from frame to frame: in each new frame it looks around
/// where the patch was for the place that matches it best (normalized cross-correlation, first
/// on a coarse grid, then pixel by pixel), and slowly updates the patch so a turning or growing
/// subject is still found. Stops when nothing matches well.
public struct PatchTracker: Sendable {
    /// Where the middle of the patch is, in pixels.
    public private(set) var x: Double
    public private(set) var y: Double
    let radius: Int
    /// How far it looks from where the patch was, in pixels.
    let reach: Int
    /// Samples of the patch, every `step` pixels, as offsets from its middle.
    private var template: [Float]
    private let offsets: [(dx: Int, dy: Int)]
    /// Below this match (−1…1) the subject is lost.
    public static let lostBelow: Float = 0.5

    public init(frame: GrayFrame, x: Double, y: Double, radius: Int, reach: Int) {
        self.x = x
        self.y = y
        self.radius = radius
        self.reach = reach
        // About 15 samples a side.
        let step = max(1, Int((Double(2 * radius) / 15).rounded()))
        var offsets: [(dx: Int, dy: Int)] = []
        for dy in stride(from: -radius, through: radius, by: step) {
            for dx in stride(from: -radius, through: radius, by: step) { offsets.append((dx, dy)) }
        }
        self.offsets = offsets
        let cx = Int(x.rounded()), cy = Int(y.rounded())
        template = offsets.map { frame.value(cx + $0.dx, cy + $0.dy) }
    }

    /// How well the patch matches `frame` with its middle at (cx, cy), −1…1.
    private func match(_ frame: GrayFrame, _ cx: Int, _ cy: Int) -> Float {
        let n = Float(offsets.count)
        var st: Float = 0, sc: Float = 0, stt: Float = 0, scc: Float = 0, stc: Float = 0
        for (i, o) in offsets.enumerated() {
            let t = template[i], c = frame.value(cx + o.dx, cy + o.dy)
            st += t; sc += c; stt += t * t; scc += c * c; stc += t * c
        }
        let covariance = stc - st * sc / n
        let spread = ((stt - st * st / n) * (scc - sc * sc / n)).squareRoot()
        return spread > 1 ? covariance / spread : 0
    }

    /// Finds the patch in the next frame. Returns how well it matched, or nil when it was lost
    /// (the position then stays where it was).
    public mutating func next(_ frame: GrayFrame) -> Float? {
        let px = Int(x.rounded()), py = Int(y.rounded())
        var best: (x: Int, y: Int, score: Float) = (px, py, -2)
        let coarse = max(2, reach / 8)
        for dy in stride(from: -reach, through: reach, by: coarse) {
            for dx in stride(from: -reach, through: reach, by: coarse) {
                let score = match(frame, px + dx, py + dy)
                if score > best.score { best = (px + dx, py + dy, score) }
            }
        }
        let around = best
        for dy in -coarse...coarse {
            for dx in -coarse...coarse {
                let score = match(frame, around.x + dx, around.y + dy)
                if score > best.score { best = (around.x + dx, around.y + dy, score) }
            }
        }
        guard best.score >= Self.lostBelow else { return nil }
        x = Double(best.x)
        y = Double(best.y)
        // Learn a little of how it looks now.
        for (i, o) in offsets.enumerated() {
            template[i] = template[i] * 0.85 + frame.value(best.x + o.dx, best.y + o.dy) * 0.15
        }
        return best.score
    }
}
