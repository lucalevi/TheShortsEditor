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

    /// The titles on screen at `time`, with how big and how opaque each is at that moment.
    func states(at time: CMTime) -> [(title: TextOverlay, scale: Double, opacity: Double)] {
        items.compactMap { item in
            guard item.range.containsTime(time) else { return nil }
            let since = (time - item.range.start).seconds
            let until = (item.range.end - time).seconds
            switch item.title.entrance {
            case .pop:
                let p = min(max(since / TitleRenderer.popSeconds, 0), 1)
                // Ease out with a slight overshoot, so it lands with a little bounce.
                let c = 1.70158
                let eased = 1 + (c + 1) * pow(p - 1, 3) + c * pow(p - 1, 2)
                return (item.title, 0.6 + 0.4 * eased, min(since / 0.06, 1))
            case .fade:
                return (item.title, 1, min(max(min(since, until) / TitleRenderer.fadeSeconds, 0), 1))
            case .none:
                return (item.title, 1, 1)
            }
        }
    }
}

/// Draws titles with Core Text. Thread-safe: it is called from the video compositor's queue.
nonisolated enum TitleRenderer {
    /// The widest a title's text may be, which keeps it (and its boxes) clear of YouTube's buttons on the right.
    static let maxWidth: CGFloat = 760
    static let popSeconds = 0.2
    static let fadeSeconds = 0.3

    private struct Look {
        var fontSize: CGFloat
        var weight: CGFloat
        var text = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        /// Stroke width as a percentage of the font size, drawn behind the letters.
        var outline: CGFloat = 0
        /// A box behind each line.
        var lineBox: CGColor?
        /// One box behind the whole title.
        var backgroundBox: CGColor?
        var shadow = false
    }

    private static func look(for style: TitleStyle) -> Look {
        let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        switch style {
        case .bold:
            return Look(fontSize: 96, weight: 0.62, outline: 24)
        case .label:
            return Look(fontSize: 76, weight: 0.56, text: black, lineBox: CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        case .marker:
            return Look(fontSize: 76, weight: 0.56, text: black, lineBox: CGColor(red: 1, green: 0.86, blue: 0.1, alpha: 1))
        case .dark:
            return Look(fontSize: 70, weight: 0.4, backgroundBox: CGColor(red: 0, green: 0, blue: 0, alpha: 0.75))
        case .simple:
            return Look(fontSize: 84, weight: 0.5, shadow: true)
        }
    }

    /// The title laid out: everything needed to draw it or to know where it will be.
    private struct Layout {
        let look: Look
        let framesetter: CTFramesetter
        let text: CFAttributedString
        /// The whole image, including room for outlines, boxes and shadows.
        let size: CGSize
        let textRect: CGRect
        /// What can actually be seen (letters and boxes), inside the image, origin at the bottom left.
        let contentRect: CGRect
    }

    private static func layout(text raw: String, style: TitleStyle, stroke: Bool = false) -> Layout? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let look = look(for: style)
        let font = CaptionRenderer.makeFont(size: look.fontSize, weight: look.weight)

        let string = CFAttributedStringCreateMutable(nil, 0)!
        CFAttributedStringReplaceString(string, CFRange(location: 0, length: 0), text as CFString)
        let all = CFRange(location: 0, length: CFAttributedStringGetLength(string))
        var alignment = CTTextAlignment.center
        // Room between lines for their boxes.
        var spacing: CGFloat = look.lineBox == nil ? 0 : look.fontSize * 0.16
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
        if stroke {
            let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
            CFAttributedStringSetAttribute(string, all, kCTForegroundColorAttributeName, black)
            CFAttributedStringSetAttribute(string, all, kCTStrokeColorAttributeName, black)
            CFAttributedStringSetAttribute(string, all, kCTStrokeWidthAttributeName, look.outline as NSNumber)
        } else {
            CFAttributedStringSetAttribute(string, all, kCTForegroundColorAttributeName, look.text)
        }

        let framesetter = CTFramesetterCreateWithAttributedString(string)
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil,
            CGSize(width: maxWidth, height: .greatestFiniteMagnitude), nil
        )
        let textSize = CGSize(width: ceil(suggested.width) + 2, height: ceil(suggested.height) + 2)
        let padding = ceil(look.fontSize * 0.45)
        let size = CGSize(width: textSize.width + padding * 2, height: textSize.height + padding * 2)
        let textRect = CGRect(origin: CGPoint(x: padding, y: padding), size: textSize)
        return Layout(
            look: look, framesetter: framesetter, text: string, size: size, textRect: textRect,
            contentRect: textRect.insetBy(dx: -look.fontSize * 0.2, dy: -look.fontSize * 0.12)
        )
    }

    /// The title as an image, centred, wrapped to `maxWidth`.
    static func image(text: String, style: TitleStyle) -> CGImage? {
        guard let layout = layout(text: text, style: style) else { return nil }
        let look = layout.look
        guard let context = CGContext(
            data: nil, width: Int(layout.size.width), height: Int(layout.size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setLineJoin(.round)

        let path = CGPath(rect: layout.textRect, transform: nil)
        let frame = CTFramesetterCreateFrame(layout.framesetter, CFRange(location: 0, length: 0), path, nil)

        if let box = look.backgroundBox {
            context.addPath(CGPath(roundedRect: layout.contentRect, cornerWidth: 18, cornerHeight: 18, transform: nil))
            context.setFillColor(box)
            context.fillPath()
        }
        if let box = look.lineBox {
            let all = CFRange(location: 0, length: CFAttributedStringGetLength(layout.text))
            for rect in CaptionRenderer.rects(of: all, in: frame, origin: layout.textRect.origin) where rect.width > 1 {
                let padded = rect.insetBy(dx: -look.fontSize * 0.2, dy: -look.fontSize * 0.08)
                context.addPath(CGPath(roundedRect: padded, cornerWidth: 12, cornerHeight: 12, transform: nil))
            }
            context.setFillColor(box)
            context.fillPath()
        }
        if look.outline > 0, let stroke = Self.layout(text: text, style: style, stroke: true) {
            CTFrameDraw(CTFramesetterCreateFrame(stroke.framesetter, CFRange(location: 0, length: 0), path, nil), context)
        }
        if look.shadow {
            context.setShadow(offset: CGSize(width: 0, height: -4), blur: 16, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.85))
        }
        CTFrameDraw(frame, context)
        return context.makeImage()
    }

    /// Where the title's image goes on the canvas (origin top left), and the part of it that can
    /// be seen. The visible part is centred on the title's position, but never leaves the canvas.
    static func placement(of title: TextOverlay) -> (image: CGRect, content: CGRect)? {
        guard let layout = layout(text: title.text, style: title.style) else { return nil }
        let canvas = Project.canvasSize
        let content = layout.contentRect
        let middle = CGFloat(title.verticalPosition) * canvas.height
        let contentTop = min(max(middle - content.height / 2, 0), max(canvas.height - content.height, 0))
        // The image's own origin is at the bottom left: its top margin is above `content.maxY`.
        let imageTop = contentTop - (layout.size.height - content.maxY)
        let imageLeft = (canvas.width - layout.size.width) / 2
        let image = CGRect(x: imageLeft, y: imageTop, width: layout.size.width, height: layout.size.height)
        let visible = CGRect(x: imageLeft + content.minX, y: contentTop, width: content.width, height: content.height)
        return (image, visible)
    }
}

/// Titles as the app needs them: style samples for the picker, and where a title is on screen.
public enum TitlePreview {
    public static func image(for style: TitleStyle) -> CGImage? {
        TitleRenderer.image(text: "Hook", style: style)
    }

    /// The visible part of the title on the 1080×1920 canvas, origin at the top left; nil when it
    /// has no text.
    public static func frame(of title: TextOverlay) -> CGRect? {
        TitleRenderer.placement(of: title)?.content
    }

    /// Where every title is drawn, for the export checks.
    public static func frames(in project: Project) -> [TextOverlay.ID: CGRect] {
        Dictionary(project.titles.compactMap { title in frame(of: title).map { (title.id, $0) } }) { a, _ in a }
    }
}
