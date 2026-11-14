import CoreGraphics
import CoreMedia
import Foundation

/// Text placed over the video for a while, such as the hook in the first seconds.
///
/// Unlike captions, a title belongs to the timeline, not to a source file: it stays at its time
/// when clips are split, deleted or moved. When the Short gets shorter than the title, the part
/// after the end is simply not shown (see `visibleRange(in:)`).
public struct TextOverlay: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var text: String
    /// The ready-made look it started from.
    public var style: TitleStyle
    /// How it actually looks: the style's look, plus any changes made to it.
    public var look: TextLook
    public var entrance: TitleEntrance
    /// When it appears, on the timeline.
    public var start: CMTime
    public var duration: CMTime
    /// Where the middle of the title sits, from 0 (top of the screen) to 1 (bottom). Not clamped to
    /// the safe area: the user may put it anywhere, and export warns when it ends up covered.
    public var verticalPosition: Double
    /// Where the middle of the title sits across, from 0 (left edge) to 1 (right edge).
    public var horizontalPosition: Double
    /// Moves with the main clip under its start (see `Project.followClips(from:)`).
    public var followsClip: Bool = true
    /// How it leaves at its end (nil: it just goes). See `ClipAnimation.swift`.
    public var exit: ClipAnimation? = nil
    /// A movement repeated while it is on screen (nil: it holds still).
    public var loop: TitleLoop? = nil
    /// Degrees, clockwise.
    public var rotation: Double = 0
    /// Set for a sticker (an emoji or symbol drawn instead of the text; `text` is then its name).
    public var sticker: Sticker? = nil
    /// Where the thing it follows in the video went, from its start (see `Stickers.swift`).
    public var track: [TrackPoint]? = nil

    public init(
        id: UUID = UUID(), text: String, style: TitleStyle = .bold, look: TextLook? = nil, entrance: TitleEntrance = .pop,
        start: CMTime, duration: CMTime, verticalPosition: Double = TitlePlacement.top.verticalPosition, horizontalPosition: Double = 0.5
    ) {
        self.id = id
        self.text = text
        self.style = style
        self.look = look ?? style.look
        self.horizontalPosition = horizontalPosition
        self.entrance = entrance
        self.start = start
        self.duration = duration
        self.verticalPosition = verticalPosition
    }

    public var end: CMTime { start + duration }
    public var range: CMTimeRange { CMTimeRange(start: start, duration: duration) }

    /// Switches to another ready-made style. Its look replaces the current one, except for the
    /// font, which stays (a brand font is usually wanted whatever the style).
    public mutating func applyStyle(_ newStyle: TitleStyle) {
        let font = look.fontFamily
        style = newStyle
        look = newStyle.look
        look.fontFamily = font
    }

    /// Whether the look differs from the style it started from.
    public var isCustomized: Bool { look != style.look }

    /// The part of the title that is on screen in `project`, or nil when it starts after the end.
    public func visibleRange(in project: Project) -> CMTimeRange? {
        let visible = range.intersection(CMTimeRange(start: .zero, duration: project.duration))
        return visible.duration > .zero ? visible : nil
    }
}

/// How a title looks. Each is a complete, tested look rather than a set of knobs.
public enum TitleStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Big white letters with a black outline.
    case bold
    /// Black letters on a white box, one box per line.
    case label
    /// Black letters on a yellow box, one box per line.
    case marker
    /// White letters on a dark box.
    case dark
    /// White letters with a soft shadow.
    case simple
    /// Light letters glowing in colour.
    case neon
    /// Only the outline of big capitals.
    case hollow
    /// White letters with a solid coloured copy behind them.
    case popShadow
    /// Yellow capitals with a thick black outline, like a comic.
    case comic
    /// White letters on a coloured box.
    case pill
    /// Typewriter letters on paper strips.
    case typewriter
    /// Thin, widely spaced capitals, like a film title.
    case cinema
    /// Handwritten with a marker.
    case handwritten

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .bold: "Bold"
        case .label: "Label"
        case .marker: "Marker"
        case .dark: "Dark Box"
        case .simple: "Simple"
        case .neon: "Neon"
        case .hollow: "Hollow"
        case .popShadow: "Pop Shadow"
        case .comic: "Comic"
        case .pill: "Pill"
        case .typewriter: "Typewriter"
        case .cinema: "Cinema"
        case .handwritten: "Handwritten"
        }
    }
}

/// How a title comes on screen.
public enum TitleEntrance: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Grows quickly into place.
    case pop
    /// Fades in, and fades out at the end.
    case fade
    /// The letters appear one after another, as if typed.
    case typewriter
    /// Slides up into place while fading in.
    case slideUp
    /// Shrinks into place from big.
    case zoom
    /// Just appears.
    case none

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .pop: "Pop"
        case .fade: "Fade"
        case .typewriter: "Type"
        case .slideUp: "Slide Up"
        case .zoom: "Zoom"
        case .none: "None"
        }
    }
}

/// The quick choices of where a title goes. It can also be dragged anywhere in the viewer.
public enum TitlePlacement: String, CaseIterable, Identifiable, Sendable {
    case top, middle, bottom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .top: "Top"
        case .middle: "Middle"
        case .bottom: "Bottom"
        }
    }

    /// Clear of YouTube's interface for a title of up to about three lines.
    public var verticalPosition: Double {
        switch self {
        case .top: 0.24
        case .middle: 0.45
        case .bottom: 0.64
        }
    }

    /// The placement at exactly `position`, or nil after the title was dragged somewhere else.
    public init?(exactly position: Double) {
        guard let match = Self.allCases.first(where: { abs($0.verticalPosition - position) < 0.005 }) else { return nil }
        self = match
    }
}

public extension TextOverlay {
    static let defaultDuration = CMTime(value: 3, timescale: 1)
    /// No title is shorter than this, so it can still be seen and grabbed on the timeline.
    static let minimumDuration = CMTime(value: 10, timescale: Project.frameRate)
}

public extension Project {
    /// Adds a title at `time` (the playhead), lasting 3 seconds or until the end of the Short.
    /// Near the end it starts earlier instead, so it is never too short to see.
    @discardableResult
    mutating func addTitle(at time: CMTime, text: String) -> TextOverlay.ID {
        let length = duration > .zero ? duration : TextOverlay.defaultDuration
        let wanted = min(TextOverlay.defaultDuration, length)
        var start = time.snappedToFrame().clamped(.zero, length)
        if length - start < wanted { start = max(.zero, length - wanted) }
        var title = TextOverlay(text: text, start: start.snappedToFrame(), duration: wanted.snappedToFrame())
        // In a styled Short, new titles match the others.
        if let style { title.takeLook(of: style) }
        titles.append(title)
        return title.id
    }

    func title(id: TextOverlay.ID) -> TextOverlay? {
        titles.first { $0.id == id }
    }

    mutating func updateTitle(_ id: TextOverlay.ID, _ change: (inout TextOverlay) -> Void) {
        guard let index = titles.firstIndex(where: { $0.id == id }) else { return }
        change(&titles[index])
    }

    mutating func removeTitle(_ id: TextOverlay.ID) {
        titles.removeAll { $0.id == id }
    }

    /// Moves a title so it starts at `start`, keeping its length, on a whole frame and inside the Short.
    mutating func moveTitle(_ id: TextOverlay.ID, to start: CMTime) {
        let end = duration
        updateTitle(id) { title in
            let latest = max(.zero, end - title.duration)
            title.start = start.snappedToFrame().clamped(.zero, latest).snappedToFrame()
        }
    }

    /// Changes how long a title stays, on a whole frame, at least `minimumDuration` and not past the end.
    mutating func setTitleDuration(_ id: TextOverlay.ID, _ newDuration: CMTime) {
        let end = duration
        updateTitle(id) { title in
            let longest = max(end - title.start, TextOverlay.minimumDuration)
            title.duration = min(max(newDuration.snappedToFrame(), TextOverlay.minimumDuration), longest).snappedToFrame()
        }
    }

    /// The titles on screen at `time`, in drawing order.
    func titlesOnScreen(at time: CMTime) -> [TextOverlay] {
        titles.filter { $0.visibleRange(in: self)?.containsTime(time) == true }
    }
}

extension TextOverlay {
    private enum CodingKeys: String, CodingKey {
        case id, text, style, look, entrance, start, duration, verticalPosition, horizontalPosition, followsClip
        case exit, loop, rotation, sticker, track
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        style = try c.decode(TitleStyle.self, forKey: .style)
        look = try c.decodeIfPresent(TextLook.self, forKey: .look) ?? style.look
        horizontalPosition = try c.decodeIfPresent(Double.self, forKey: .horizontalPosition) ?? 0.5
        entrance = try c.decode(TitleEntrance.self, forKey: .entrance)
        start = try c.decodeTime(forKey: .start)
        duration = try c.decodeTime(forKey: .duration)
        verticalPosition = try c.decode(Double.self, forKey: .verticalPosition)
        followsClip = try c.decodeIfPresent(Bool.self, forKey: .followsClip) ?? true
        exit = try c.decodeIfPresent(ClipAnimation.self, forKey: .exit)
        loop = try c.decodeIfPresent(TitleLoop.self, forKey: .loop)
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        sticker = try c.decodeIfPresent(Sticker.self, forKey: .sticker)
        track = try c.decodeIfPresent([TrackPoint].self, forKey: .track)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(text, forKey: .text)
        try c.encode(style, forKey: .style)
        try c.encode(look, forKey: .look)
        try c.encode(horizontalPosition, forKey: .horizontalPosition)
        try c.encode(entrance, forKey: .entrance)
        try c.encode(time: start, forKey: .start)
        try c.encode(time: duration, forKey: .duration)
        try c.encode(verticalPosition, forKey: .verticalPosition)
        try c.encode(followsClip, forKey: .followsClip)
        try c.encodeIfPresent(exit, forKey: .exit)
        try c.encodeIfPresent(loop, forKey: .loop)
        if rotation != 0 { try c.encode(rotation, forKey: .rotation) }
        try c.encodeIfPresent(sticker, forKey: .sticker)
        try c.encodeIfPresent(track, forKey: .track)
    }
}
