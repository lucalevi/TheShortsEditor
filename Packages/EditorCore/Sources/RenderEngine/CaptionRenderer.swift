import CoreGraphics
import CoreMedia
import CoreText
import EditorCore
import Foundation

/// The captions of a whole Short, ready to draw: pages plus how they look and where they go.
nonisolated struct CaptionTrack: Sendable {
    let pages: [CaptionPage]
    let settings: CaptionSettings
    var style: CaptionStyle { settings.style }
    var verticalPosition: Double { settings.verticalPosition }

    init(project: Project) {
        pages = project.captions.isVisible ? CaptionLayout.pages(in: project) : []
        settings = project.captions
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

    /// The colour key words get when no accent is chosen: one that differs from the spoken word's.
    static func keywordColor(for style: CaptionStyle) -> RGBA {
        style == .bold ? RGBA(0.35, 0.95, 0.45) : .yellow
    }

    /// The style's look with the user's changes (font size, colours).
    private static func look(for settings: CaptionSettings) -> Look {
        var look = look(for: settings.style)
        look.fontSize *= CGFloat(min(max(settings.sizeScale, CaptionSettings.sizeRange.lowerBound), CaptionSettings.sizeRange.upperBound))
        if let text = settings.textColor { look.text = TitleRenderer.cgColor(text) }
        if let accent = settings.accentColor {
            if look.currentWord != nil { look.currentWord = TitleRenderer.cgColor(accent) }
            if look.wordBox != nil { look.wordBox = TitleRenderer.cgColor(accent) }
        }
        return look
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

    /// The page as an image, with `currentWord` emphasised when the style does that, the words at
    /// `keywords` in the accent colour, and `emoji` above.
    static func image(words: [String], currentWord: Int?, style: CaptionStyle) -> CGImage? {
        var settings = CaptionSettings()
        settings.style = style
        return image(words: words, keywords: [], currentWord: currentWord, emoji: nil, settings: settings)
    }

    static func image(words: [String], keywords: Set<Int>, currentWord: Int?, emoji: String?, settings: CaptionSettings) -> CGImage? {
        let style = settings.style
        var look = look(for: settings)
        let family = settings.fontFamily
        let shown = words.map { style.isUppercase ? $0.uppercased() : $0 }
        let text = shown.joined(separator: " ")
        guard !text.isEmpty else { return nil }
        if look.pops {
            // The punchy styles read best on one line: shrink a long page a little rather than wrap it.
            let plain = CFAttributedStringCreate(nil, text as CFString, [kCTFontAttributeName: makeFont(size: look.fontSize, weight: Double(look.weight), family: family)] as CFDictionary)!
            let kerning = look.wordBox == nil ? 0 : look.fontSize * 0.22 * CGFloat(shown.count - 1)
            let width = CTLineGetTypographicBounds(CTLineCreateWithAttributedString(plain), nil, nil, nil) + kerning + look.fontSize * 0.1
            // The spoken word is drawn a little bigger: leave room for it.
            let needed = style.highlightsCurrentWord ? width * 1.12 : width
            if needed > maxWidth {
                look.fontSize = max(look.fontSize * maxWidth / needed, look.fontSize * 0.7).rounded(.down)
            }
        }
        let font = makeFont(size: look.fontSize, weight: Double(look.weight), family: family)
        // The spoken word grows a little in the punchy styles.
        let bigFont = look.pops && style.highlightsCurrentWord ? makeFont(size: look.fontSize * 1.12, weight: Double(look.weight), family: family) : font
        let keywordColor = TitleRenderer.cgColor(settings.accentColor ?? keywordColor(for: style))

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
            if let current, bigFont !== font {
                CFAttributedStringSetAttribute(string, current, kCTFontAttributeName, bigFont)
            }
            if stroke {
                CFAttributedStringSetAttribute(string, all, kCTForegroundColorAttributeName, CGColor(red: 0, green: 0, blue: 0, alpha: 1))
                CFAttributedStringSetAttribute(string, all, kCTStrokeColorAttributeName, CGColor(red: 0, green: 0, blue: 0, alpha: 1))
                CFAttributedStringSetAttribute(string, all, kCTStrokeWidthAttributeName, look.outline as NSNumber)
            } else {
                CFAttributedStringSetAttribute(string, all, kCTForegroundColorAttributeName, look.text)
                if settings.showsKeywords {
                    for index in keywords where wordRanges.indices.contains(index) {
                        CFAttributedStringSetAttribute(string, wordRanges[index], kCTForegroundColorAttributeName, keywordColor)
                    }
                }
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
        // Room above the text for the emoji.
        let emojiLine: CTLine? = settings.showsEmoji ? emoji.map { emoji in
            let emojiFont = CTFontCreateWithName("AppleColorEmoji" as CFString, look.fontSize * 1.05, nil)
            return CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, emoji as CFString, [kCTFontAttributeName: emojiFont] as CFDictionary)!)
        } : nil
        let emojiHeight: CGFloat = emojiLine == nil ? 0 : ceil(look.fontSize * 1.3)
        let size = CGSize(width: max(textSize.width + padding * 2, emojiHeight * 1.6), height: textSize.height + padding * 2 + emojiHeight)
        let textRect = CGRect(origin: CGPoint(x: (size.width - textSize.width) / 2, y: padding), size: textSize)

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
        if let emojiLine {
            let width = CTLineGetTypographicBounds(emojiLine, nil, nil, nil)
            context.setShadow(offset: .zero, blur: 0, color: nil)
            context.textPosition = CGPoint(x: (size.width - width) / 2, y: textRect.maxY + emojiHeight * 0.18)
            CTLineDraw(emojiLine, context)
        }
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

    /// A font of `family` (bold when `weight` is above 0.3), or the system font at `weight` when
    /// there is no family or it isn't installed.
    static func makeFont(size: CGFloat, weight: Double, family: String?) -> CTFont {
        if let family, !family.isEmpty {
            var attributes: [CFString: Any] = [kCTFontFamilyNameAttribute: family]
            if weight > 0.3 { attributes[kCTFontTraitsAttribute] = [kCTFontSymbolicTrait: CTFontSymbolicTraits.traitBold.rawValue] }
            let wanted = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
            let mandatory: Set<CFString> = [kCTFontFamilyNameAttribute]
            if let match = CTFontDescriptorCreateMatchingFontDescriptor(wanted, mandatory as CFSet) {
                return CTFontCreateWithFontDescriptor(match, size, nil)
            }
        }
        return makeFont(size: size, weight: CGFloat(weight))
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

    /// A sample with the Short's own caption settings (font, size, colours), a key word and an emoji.
    public static func image(for settings: CaptionSettings) -> CGImage? {
        CaptionRenderer.image(words: settings.style == .oneWord ? ["Wow"] : ["Make", "it", "pop"], keywords: settings.style == .oneWord ? [] : [2],
                              currentWord: 1, emoji: "🔥", settings: settings)
    }

    /// Where the caption on screen at `time` is (canvas pixels, origin top left), for dragging it.
    public static func frame(in project: Project, at time: CMTime) -> CGRect? {
        let track = CaptionTrack(project: project)
        guard let state = track.state(at: time),
              let image = CaptionRenderer.image(words: state.page.words.map(\.text), keywords: [], currentWord: nil,
                                                emoji: state.page.emoji, settings: track.settings)
        else { return nil }
        let size = CGSize(width: image.width, height: image.height)
        return CGRect(x: (Project.canvasSize.width - size.width) / 2, y: track.top(forHeight: size.height), width: size.width, height: size.height)
    }
}
