import CoreGraphics
import CoreMedia
import CoreText
import EditorCore
import Foundation

/// The captions of a whole Short, ready to draw: pages plus how they look and where they go.
nonisolated struct CaptionTrack: Sendable {
    let pages: [CaptionPage]
    let style: CaptionStyle
    let verticalPosition: Double

    init(project: Project) {
        pages = project.captions.isVisible ? CaptionLayout.pages(in: project) : []
        style = project.captions.style
        verticalPosition = project.captions.verticalPosition
    }

    /// What to draw at `time`: the page, the word being spoken, and how far the page's
    /// entrance has got (0 when it just appeared, 1 once it has settled).
    func state(at time: CMTime) -> (page: CaptionPage, word: Int, entrance: Double)? {
        guard let page = CaptionLayout.page(at: time, in: pages) else { return nil }
        let since = (time - page.range.start).seconds
        return (page, page.wordIndex(at: time), min(max(since / CaptionRenderer.entranceSeconds, 0), 1))
    }

    /// The top edge of a caption `height` pixels tall, in canvas coordinates (origin top left).
    /// Kept clear of the areas YouTube covers.
    func top(forHeight height: CGFloat) -> CGFloat {
        let range = SafeZone.captionRange
        let middle = CGFloat(min(max(verticalPosition, range.lowerBound), range.upperBound)) * Project.canvasSize.height
        let lowest = Project.canvasSize.height - SafeZone.bottom - height
        return max(min(middle - height / 2, lowest), SafeZone.top)
    }
}

/// Draws caption pages with Core Text. Thread-safe: it is called from the video compositor's queue.
nonisolated enum CaptionRenderer {
    /// The widest a caption may be, which keeps it clear of YouTube's buttons on the right.
    static let maxWidth: CGFloat = 780
    /// How long a page takes to pop in, for the styles that animate.
    static let entranceSeconds = 0.12

    private struct Look {
        var fontSize: CGFloat
        /// Core Text weight trait, from -1 (thin) to 1 (black).
        var weight: CGFloat
        var text = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        var currentWord: CGColor?
        /// Stroke width as a percentage of the font size, drawn behind the letters.
        var outline: CGFloat = 0
        var wordBox: CGColor?
        var backgroundBox: CGColor?
        var shadow = false
        var pops = false
    }

    private static func look(for style: CaptionStyle) -> Look {
        switch style {
        case .bold:
            return Look(fontSize: 100, weight: 0.62, currentWord: CGColor(red: 1, green: 0.86, blue: 0.1, alpha: 1), outline: 24, pops: true)
        case .highlight:
            return Look(fontSize: 92, weight: 0.56, outline: 20, wordBox: CGColor(red: 0.16, green: 0.78, blue: 0.36, alpha: 1), pops: true)
        case .oneWord:
            return Look(fontSize: 136, weight: 0.62, outline: 22, pops: true)
        case .classic:
            return Look(fontSize: 54, weight: 0.3, backgroundBox: CGColor(red: 0, green: 0, blue: 0, alpha: 0.7))
        case .minimal:
            return Look(fontSize: 62, weight: 0.4, shadow: true)
        }
    }

    static func animates(_ style: CaptionStyle) -> Bool { look(for: style).pops }

    /// The page as an image, with `currentWord` emphasised when the style does that.
    static func image(words: [String], currentWord: Int?, style: CaptionStyle) -> CGImage? {
        var look = look(for: style)
        let shown = words.map { style.isUppercase ? $0.uppercased() : $0 }
        let text = shown.joined(separator: " ")
        guard !text.isEmpty else { return nil }
        if look.pops {
            // The punchy styles read best on one line: shrink a long page a little rather than wrap it.
            let plain = CFAttributedStringCreate(nil, text as CFString, [kCTFontAttributeName: makeFont(size: look.fontSize, weight: look.weight)] as CFDictionary)!
            let kerning = look.wordBox == nil ? 0 : look.fontSize * 0.22 * CGFloat(shown.count - 1)
            let width = CTLineGetTypographicBounds(CTLineCreateWithAttributedString(plain), nil, nil, nil) + kerning + look.fontSize * 0.1
            if width > maxWidth {
                look.fontSize = max(look.fontSize * maxWidth / width, look.fontSize * 0.7).rounded(.down)
            }
        }
        let font = makeFont(size: look.fontSize, weight: look.weight)

        // Where each word is in the string, for colouring and boxing the current one.
        var wordRanges: [CFRange] = []
        var location = 0
        for word in shown {
            let length = (word as NSString).length
            wordRanges.append(CFRange(location: location, length: length))
            location += length + 1
        }
        let current = style.highlightsCurrentWord ? currentWord.flatMap { wordRanges.indices.contains($0) ? wordRanges[$0] : nil } : nil

        func attributed(stroke: Bool) -> CFAttributedString {
            let string = CFAttributedStringCreateMutable(nil, 0)!
            CFAttributedStringReplaceString(string, CFRange(location: 0, length: 0), text as CFString)
            let all = CFRange(location: 0, length: CFAttributedStringGetLength(string))
            var alignment = CTTextAlignment.center
            let paragraph = withUnsafeMutableBytes(of: &alignment) { pointer in
                var setting = CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: pointer.baseAddress!)
                return CTParagraphStyleCreate(&setting, 1)
            }
            CFAttributedStringSetAttribute(string, all, kCTFontAttributeName, font)
            CFAttributedStringSetAttribute(string, all, kCTParagraphStyleAttributeName, paragraph)
            if look.wordBox != nil {
                // Room between words for the box around the current one.
                for range in wordRanges.dropLast() {
                    CFAttributedStringSetAttribute(string, CFRange(location: range.location + range.length, length: 1), kCTKernAttributeName, look.fontSize * 0.22 as NSNumber)
                }
            }
            if stroke {
                CFAttributedStringSetAttribute(string, all, kCTForegroundColorAttributeName, CGColor(red: 0, green: 0, blue: 0, alpha: 1))
                CFAttributedStringSetAttribute(string, all, kCTStrokeColorAttributeName, CGColor(red: 0, green: 0, blue: 0, alpha: 1))
                CFAttributedStringSetAttribute(string, all, kCTStrokeWidthAttributeName, look.outline as NSNumber)
            } else {
                CFAttributedStringSetAttribute(string, all, kCTForegroundColorAttributeName, look.text)
                if let current, let color = look.currentWord {
                    CFAttributedStringSetAttribute(string, current, kCTForegroundColorAttributeName, color)
                }
            }
            return string
        }

        let fill = attributed(stroke: false)
        let framesetter = CTFramesetterCreateWithAttributedString(fill)
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil,
            CGSize(width: maxWidth, height: .greatestFiniteMagnitude), nil
        )
        let textSize = CGSize(width: ceil(suggested.width) + 2, height: ceil(suggested.height) + 2)
        let padding = ceil(look.fontSize * 0.4)
        let size = CGSize(width: textSize.width + padding * 2, height: textSize.height + padding * 2)
        let textRect = CGRect(origin: CGPoint(x: padding, y: padding), size: textSize)

        guard let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setLineJoin(.round)

        let path = CGPath(rect: textRect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)

        if let box = look.backgroundBox {
            let rect = textRect.insetBy(dx: -padding * 0.6, dy: -padding * 0.35)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: 14, cornerHeight: 14, transform: nil))
            context.setFillColor(box)
            context.fillPath()
        }
        if let current, let color = look.wordBox {
            for rect in rects(of: current, in: frame, origin: textRect.origin) {
                let box = rect.insetBy(dx: -look.fontSize * 0.14, dy: -look.fontSize * 0.06)
                context.addPath(CGPath(roundedRect: box, cornerWidth: 16, cornerHeight: 16, transform: nil))
            }
            context.setFillColor(color)
            context.fillPath()
        }
        if look.outline > 0 {
            CTFrameDraw(CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(attributed(stroke: true)), CFRange(location: 0, length: 0), path, nil), context)
        }
        if look.shadow {
            context.setShadow(offset: CGSize(width: 0, height: -4), blur: 14, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.85))
        }
        CTFrameDraw(frame, context)
        return context.makeImage()
    }

    /// The boxes a range of characters takes up, one per line it is on.
    static func rects(of range: CFRange, in frame: CTFrame, origin: CGPoint) -> [CGRect] {
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        var result: [CGRect] = []
        for (line, lineOrigin) in zip(lines, origins) {
            let lineRange = CTLineGetStringRange(line)
            let start = max(range.location, lineRange.location)
            let end = min(range.location + range.length, lineRange.location + lineRange.length)
            guard start < end else { continue }
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            let x0 = CTLineGetOffsetForStringIndex(line, start, nil)
            let x1 = CTLineGetOffsetForStringIndex(line, end, nil)
            result.append(CGRect(
                x: origin.x + lineOrigin.x + x0,
                y: origin.y + lineOrigin.y - descent,
                width: x1 - x0,
                height: ascent + descent
            ))
        }
        return result
    }

    static func makeFont(size: CGFloat, weight: CGFloat) -> CTFont {
        let base = CTFontCreateUIFontForLanguage(.system, size, nil)!
        let traits = [kCTFontWeightTrait: weight] as CFDictionary
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(
            CTFontCopyFontDescriptor(base),
            [kCTFontTraitsAttribute: traits] as CFDictionary
        )
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }
}

/// Sample images of each caption style, drawn by the same code as the video, for the style picker.
public enum CaptionPreview {
    public static func image(for style: CaptionStyle) -> CGImage? {
        CaptionRenderer.image(words: style == .oneWord ? ["Wow"] : ["Make", "it", "pop"], currentWord: 1, style: style)
    }
}
