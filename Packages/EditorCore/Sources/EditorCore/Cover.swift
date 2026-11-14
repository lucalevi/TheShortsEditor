import CoreMedia
import Foundation

// Stage L: the cover (thumbnail) of a Short: one of its frames with big text over it, saved as a
// 1080×1920 picture to upload to YouTube. It is also the Short's picture in the home window.

public struct ShortCover: Codable, Equatable, Sendable {
    /// The moment of the Short it shows.
    public var time: CMTime
    /// Big text over it ("" for none).
    public var text: String
    /// Where the text sits, 0 (top) … 1 (bottom), as a fraction of the canvas height.
    public var textPosition: Double
    /// Whether the captions showing at that moment are on it too.
    public var showsCaptions: Bool

    public init(time: CMTime, text: String = "", textPosition: Double = 0.42, showsCaptions: Bool = false) {
        self.time = time
        self.text = text
        self.textPosition = textPosition
        self.showsCaptions = showsCaptions
    }

    /// The letter size of the cover text: big, as a cover is seen small.
    public static let textSize = 150.0

    private enum CodingKeys: String, CodingKey { case time, text, textPosition, showsCaptions }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        time = try c.decodeTime(forKey: .time)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        textPosition = try c.decodeIfPresent(Double.self, forKey: .textPosition) ?? 0.42
        showsCaptions = try c.decodeIfPresent(Bool.self, forKey: .showsCaptions) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(time: time, forKey: .time)
        try c.encode(text, forKey: .text)
        try c.encode(textPosition, forKey: .textPosition)
        try c.encode(showsCaptions, forKey: .showsCaptions)
    }
}

public extension Project {
    /// A cover to start from: a frame a second in (past the opening fade), with the hook title's
    /// words when there is one at the start.
    var suggestedCover: ShortCover {
        let second = CMTime(value: 1, timescale: 1)
        let time = duration > second + second ? second : CMTimeMultiplyByRatio(duration, multiplier: 1, divisor: 2).snappedToFrame()
        let hook = titles.first { $0.sticker == nil && $0.start < CMTime(value: 3, timescale: 1) }?.text ?? ""
        return ShortCover(time: time, text: hook)
    }

    /// The Short as the cover is drawn from it: titles on screen at that moment give way to the
    /// cover's text (made big, in the Short's style), captions only if asked.
    func coverProject(_ cover: ShortCover) -> Project {
        var project = self
        let time = cover.time.clamped(.zero, max(.zero, duration - .oneFrame))
        if !cover.showsCaptions { project.captions.isVisible = false }
        let text = cover.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return project }
        // A title already on screen saying the same thing would show twice.
        project.titles.removeAll { $0.sticker == nil && CMTimeRange(start: $0.start, duration: $0.duration).containsTime(time) }
        var title = TextOverlay(
            text: text, start: time, duration: CMTime(value: 1, timescale: 1),
            verticalPosition: cover.textPosition)
        if let style { title.takeLook(of: style) }
        title.entrance = .none
        title.exit = nil
        title.loop = nil
        title.look.size = ShortCover.textSize
        title.followsClip = false
        project.titles.append(title)
        return project
    }

    /// When the home window's picture of the Short is taken: its cover's moment when it has one.
    var posterTime: CMTime? { cover.map { $0.time.clamped(.zero, max(.zero, duration - .oneFrame)) } }
}
