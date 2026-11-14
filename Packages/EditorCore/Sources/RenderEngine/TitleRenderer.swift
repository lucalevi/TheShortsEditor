import CoreGraphics
import CoreMedia
import CoreText
import EditorCore
import Foundation

/// The titles of a whole Short, ready to draw, with the time each is actually on screen.
nonisolated struct TitleTrack: Sendable {
    struct Item: Sendable {
        let title: TextOverlay
        /// Cut to the length of the Short.
        let range: CMTimeRange
    }

    let items: [Item]

    init(project: Project) {
        items = project.titles.compactMap { title in
            title.visibleRange(in: project).map { Item(title: title, range: $0) }
        }
    }

    /// How a title is drawn at one moment of its entrance.
    struct State: Sendable {
        let title: TextOverlay
        var scale: Double = 1
        var opacity: Double = 1
        /// Moved down by this many canvas pixels (sliding in, a loop, following something).
        var yOffset: Double = 0
        /// Moved right by this many canvas pixels.
        var xOffset: Double = 0
        /// Degrees, clockwise (its own turn plus a loop's).
        var rotation: Double = 0
        var blur: Double = 0
        /// For the typewriter entrance: how many characters are showing (nil: all).
        var visibleCharacters: Int?
    }

    /// The titles on screen at `time`, with how each looks at that moment of its entrance.
    func states(at time: CMTime) -> [State] {
        items.compactMap { item in
            guard item.range.containsTime(time) else { return nil }
            let since = (time - item.range.start).seconds
            let until = (item.range.end - time).seconds
            var state = State(title: item.title)
            switch item.title.entrance {
            case .pop:
                let p = min(max(since / TitleRenderer.popSeconds, 0), 1)
                // Ease out with a slight overshoot, so it lands with a little bounce.
                let c = 1.70158
                let eased = 1 + (c + 1) * pow(p - 1, 3) + c * pow(p - 1, 2)
                state.scale = 0.6 + 0.4 * eased
                state.opacity = min(since / 0.06, 1)
            case .fade:
                state.opacity = min(max(min(since, until) / TitleRenderer.fadeSeconds, 0), 1)
            case .typewriter:
                let count = item.title.text.count
                let typing = min(Double(count) * TitleRenderer.secondsPerCharacter, item.range.duration.seconds * 0.4, 1.5)
                let shown = typing > 0 ? Int((Double(count) * since / typing).rounded(.up)) : count
                state.visibleCharacters = min(max(shown, 1), count)
            case .slideUp:
                let p = min(max(since / TitleRenderer.slideSeconds, 0), 1)
                let eased = 1 - pow(1 - p, 3)
                state.yOffset = 80 * (1 - eased)
                state.opacity = eased
            case .zoom:
                let p = min(max(since / TitleRenderer.slideSeconds, 0), 1)
                let eased = 1 - pow(1 - p, 3)
                state.scale = 1.6 - 0.6 * eased
                state.opacity = min(p * 2, 1)
            case .none:
                break
            }
            // Its own turn, then a loop and the way out, then where what it follows has gone.
            let offset = time - item.range.start
            let canvas = Project.canvasSize
            state.rotation = item.title.rotation
            if let motion = item.title.motionState(atOffset: offset) {
                state.scale *= motion.scale
                state.opacity *= motion.opacity
                state.rotation += motion.rotation
                state.xOffset += motion.offsetX * canvas.width
                state.yOffset += motion.offsetY * canvas.height
                state.blur = motion.blur
            }
            let shift = item.title.trackShift(atOffset: offset)
            state.xOffset += shift.x * canvas.width
            state.yOffset += shift.y * canvas.height
            return state
        }
    }
}

/// Draws titles with Core Text. Thread-safe: it is called from the video compositor's queue.
nonisolated enum TitleRenderer {
    /// The widest a title's text may be, which keeps it (and its boxes) clear of YouTube's buttons on the right.
    static let maxWidth: CGFloat = 760
    static let popSeconds = 0.2
    static let fadeSeconds = 0.3
    static let slideSeconds = 0.35
    static let secondsPerCharacter = 0.045

    /// The title laid out: everything needed to draw it or to know where it will be.
    private struct Layout {
        let look: TextLook
        let framesetter: CTFramesetter
        let text: CFAttributedString
        /// The whole image, including room for outlines, boxes and shadows.
        let size: CGSize
        let textRect: CGRect
        /// What can actually be seen (letters and boxes), inside the image, origin at the bottom left.
        let contentRect: CGRect
    }

    static func cgColor(_ color: RGBA) -> CGColor {
        CGColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }

    /// The text as it is shown (in capitals when the look says so).
    private static func shownText(_ raw: String, _ look: TextLook) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return look.uppercase ? text.uppercased() : text
    }

    /// `visible`: how many characters are drawn (the rest take their place but are clear).
    private static func layout(text raw: String, look: TextLook, stroke: Bool = false, visible: Int? = nil) -> Layout? {
        let text = shownText(raw, look)
        guard !text.isEmpty else { return nil }
        let size = CGFloat(look.size)
        let font = CaptionRenderer.makeFont(size: size, weight: look.weight, family: look.fontFamily)

        let string = CFAttributedStringCreateMutable(nil, 0)!
        CFAttributedStringReplaceString(string, CFRange(location: 0, length: 0), text as CFString)
        let length = CFAttributedStringGetLength(string)
        let all = CFRange(location: 0, length: length)
        var alignment = CTTextAlignment.center
        // Room between lines for their boxes.
        var spacing: CGFloat = look.boxColor != nil && look.boxPerLine ? size * 0.16 : 0
        let paragraph = withUnsafeMutableBytes(of: &alignment) { alignmentPointer in
            withUnsafeMutableBytes(of: &spacing) { spacingPointer in
                var settings = [
                    CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: alignmentPointer.baseAddress!),
                    CTParagraphStyleSetting(spec: .lineSpacingAdjustment, valueSize: MemoryLayout<CGFloat>.size, value: spacingPointer.baseAddress!),
                ]
                return CTParagraphStyleCreate(&settings, settings.count)
            }
        }
        CFAttributedStringSetAttribute(string, all, kCTFontAttributeName, font)
        CFAttributedStringSetAttribute(string, all, kCTParagraphStyleAttributeName, paragraph)
        if look.letterSpacing != 0 {
            CFAttributedStringSetAttribute(string, all, kCTKernAttributeName, (size * CGFloat(look.letterSpacing) / 100) as NSNumber)
        }
        if stroke, let outline = look.outlineColor {
            let color = cgColor(outline)
            CFAttributedStringSetAttribute(string, all, kCTForegroundColorAttributeName, color)
            CFAttributedStringSetAttribute(string, all, kCTStrokeColorAttributeName, color)
            CFAttributedStringSetAttribute(string, all, kCTStrokeWidthAttributeName, look.outlineWidth as NSNumber)
        } else {
            CFAttributedStringSetAttribute(string, all, kCTForegroundColorAttributeName, cgColor(look.textColor))
        }
        if let visible, visible < length {
            let clear = CGColor(red: 0, green: 0, blue: 0, alpha: 0)
            let hidden = CFRange(location: visible, length: length - visible)
            CFAttributedStringSetAttribute(string, hidden, kCTForegroundColorAttributeName, clear)
            CFAttributedStringSetAttribute(string, hidden, kCTStrokeColorAttributeName, clear)
        }

        let framesetter = CTFramesetterCreateWithAttributedString(string)
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil,
            CGSize(width: maxWidth, height: .greatestFiniteMagnitude), nil
        )
        let textSize = CGSize(width: ceil(suggested.width) + 2, height: ceil(suggested.height) + 2)
        // Room for outlines and shadows, more for a glow.
        let padding = ceil(size * (look.glowColor != nil ? 0.7 : 0.45))
        let imageSize = CGSize(width: textSize.width + padding * 2, height: textSize.height + padding * 2)
        let textRect = CGRect(origin: CGPoint(x: padding, y: padding), size: textSize)
        return Layout(
            look: look, framesetter: framesetter, text: string, size: imageSize, textRect: textRect,
            contentRect: textRect.insetBy(dx: -size * 0.2, dy: -size * 0.12)
        )
    }

    /// The title as an image, centred, wrapped to `maxWidth`. With `visibleCharacters`, only
    /// that many letters are drawn (typing), in their final places.
    static func image(text: String, look: TextLook, visibleCharacters: Int? = nil) -> CGImage? {
        guard let layout = layout(text: text, look: look, visible: visibleCharacters) else { return nil }
        let size = CGFloat(look.size)
        guard
            let context = CGContext(
                data: nil, width: Int(layout.size.width), height: Int(layout.size.height), bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }
        context.setLineJoin(.round)

        let path = CGPath(rect: layout.textRect, transform: nil)
        let frame = CTFramesetterCreateFrame(layout.framesetter, CFRange(location: 0, length: 0), path, nil)
        let length = CFAttributedStringGetLength(layout.text)
        let shown = CFRange(location: 0, length: min(visibleCharacters ?? length, length))

        if let box = look.boxColor {
            if look.boxPerLine {
                for rect in CaptionRenderer.rects(of: shown, in: frame, origin: layout.textRect.origin) where rect.width > 1 {
                    let padded = rect.insetBy(dx: -size * 0.2, dy: -size * 0.08)
                    context.addPath(CGPath(roundedRect: padded, cornerWidth: 12, cornerHeight: 12, transform: nil))
                }
            } else {
                context.addPath(CGPath(roundedRect: layout.contentRect, cornerWidth: 18, cornerHeight: 18, transform: nil))
            }
            context.setFillColor(cgColor(box))
            context.fillPath()
        }
        if look.outlineColor != nil, look.outlineWidth > 0,
            let stroke = Self.layout(text: text, look: look, stroke: true, visible: visibleCharacters)
        {
            CTFrameDraw(CTFramesetterCreateFrame(stroke.framesetter, CFRange(location: 0, length: 0), path, nil), context)
        }
        if let pop = look.popShadowColor, let solid = Self.layout(text: text, look: recoloured(look, pop), visible: visibleCharacters) {
            // A solid copy of the letters, down and to the right.
            let shift = max(4, size * 0.07)
            context.saveGState()
            context.translateBy(x: shift, y: -shift)
            CTFrameDraw(CTFramesetterCreateFrame(solid.framesetter, CFRange(location: 0, length: 0), path, nil), context)
            context.restoreGState()
        }
        if let glow = look.glowColor {
            // Light around the letters: the letters drawn twice with a wide coloured shadow.
            context.saveGState()
            context.setShadow(offset: .zero, blur: size * 0.45, color: cgColor(glow))
            CTFrameDraw(frame, context)
            context.setShadow(offset: .zero, blur: size * 0.15, color: cgColor(glow))
            CTFrameDraw(frame, context)
            context.restoreGState()
        }
        if look.shadow {
            context.setShadow(offset: CGSize(width: 0, height: -4), blur: 16, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.85))
        }
        CTFrameDraw(frame, context)
        return context.makeImage()
    }

    private static func recoloured(_ look: TextLook, _ color: RGBA) -> TextLook {
        var copy = look
        copy.textColor = color
        copy.outlineColor = nil
        copy.glowColor = nil
        return copy
    }

    /// A title or sticker as an image (see `StickerRenderer` for stickers).
    static func image(of title: TextOverlay, visibleCharacters: Int? = nil) -> CGImage? {
        if let sticker = title.sticker { return StickerRenderer.image(sticker) }
        return image(text: title.text, look: title.look, visibleCharacters: visibleCharacters)
    }

    /// A title drawn in a ready-made style's look.
    static func image(text: String, style: TitleStyle) -> CGImage? {
        image(text: text, look: style.look)
    }

    /// Where the title's image goes on the canvas (origin top left), and the part of it that can
    /// be seen. The visible part is centred on the title's position, but never leaves the canvas.
    static func placement(of title: TextOverlay) -> (image: CGRect, content: CGRect)? {
        let imageSize: CGSize, content: CGRect
        if let sticker = title.sticker {
            guard let size = StickerRenderer.image(sticker).map({ CGSize(width: $0.width, height: $0.height) }) else { return nil }
            imageSize = size
            content = CGRect(origin: .zero, size: size)
        } else {
            guard let layout = layout(text: title.text, look: title.look) else { return nil }
            imageSize = layout.size
            content = layout.contentRect
        }
        let canvas = Project.canvasSize
        let middle = CGFloat(title.verticalPosition) * canvas.height
        let contentTop = min(max(middle - content.height / 2, 0), max(canvas.height - content.height, 0))
        let centre = CGFloat(title.horizontalPosition) * canvas.width
        let contentLeft = min(max(centre - content.width / 2, 0), max(canvas.width - content.width, 0))
        // The image's own origin is at the bottom left: its top margin is above `content.maxY`.
        let imageTop = contentTop - (imageSize.height - content.maxY)
        let imageLeft = contentLeft - content.minX
        let image = CGRect(x: imageLeft, y: imageTop, width: imageSize.width, height: imageSize.height)
        let visible = CGRect(x: contentLeft, y: contentTop, width: content.width, height: content.height)
        return (image, visible)
    }
}

/// Titles as the app needs them: style samples for the picker, and where a title is on screen.
public enum TitlePreview {
    public static func image(for style: TitleStyle) -> CGImage? {
        TitleRenderer.image(text: "Hook", look: style.look)
    }

    /// A sample of a look, for saved styles and the font menu.
    public static func image(for look: TextLook, text: String = "Hook") -> CGImage? {
        TitleRenderer.image(text: text, look: look)
    }

    /// The visible part of the title on the 1080×1920 canvas, origin at the top left; nil when it
    /// has no text.
    public static func frame(of title: TextOverlay) -> CGRect? {
        TitleRenderer.placement(of: title)?.content
    }

    /// The same at timeline `time`, moved with what it follows.
    public static func frame(of title: TextOverlay, at time: CMTime) -> CGRect? {
        guard let frame = frame(of: title) else { return nil }
        let shift = title.trackShift(atOffset: time - title.start)
        let canvas = Project.canvasSize
        return frame.offsetBy(dx: shift.x * canvas.width, dy: shift.y * canvas.height)
    }

    /// A sticker on its own, for the sticker grid.
    public static func image(for sticker: Sticker) -> CGImage? {
        StickerRenderer.image(sticker)
    }

    /// Where every title is drawn, for the export checks.
    public static func frames(in project: Project) -> [TextOverlay.ID: CGRect] {
        Dictionary(project.titles.compactMap { title in frame(of: title).map { (title.id, $0) } }) { a, _ in a }
    }
}
