import CoreGraphics
import CoreMedia
import CoreText
import EditorCore
import Foundation

/// One caption as it is drawn at one moment: its words, which one is being spoken and how far
/// that word has got (for the looks whose words move or fill).
nonisolated struct CaptionDrawing: Hashable, Sendable {
    var words: [String]
    var keywords: Set<Int> = []
    var currentWord: Int?
    /// Words followed by a new line.
    var lineBreaks: Set<Int> = []
    var emoji: String?
    /// The second line, in another language.
    var translation: String?
    /// How far through the spoken word, from 0 to 1 (karaoke fill).
    var wordProgress: Double = 1
    /// Seconds since the spoken word started, up to `CaptionRenderer.bounceSeconds` (bounce).
    var wordAge: Double = 1
}

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

    /// What to draw at `time`: the page, how it looks at that moment, and how far the page's
    /// entrance has got (0 when it just appeared, 1 once it has settled).
    func state(at time: CMTime) -> (page: CaptionPage, drawing: CaptionDrawing, entrance: Double)? {
        guard let page = CaptionLayout.page(at: time, in: pages) else { return nil }
        let since = (time - page.range.start).seconds
        let index = page.wordIndex(at: time)
        let word = page.words[index]
        let age = (time - word.range.start).seconds
        var drawing = drawing(for: page, currentWord: index)
        if CaptionRenderer.fills(style) {
            // Eight steps per word are smooth enough and keep the number of images small.
            let progress = word.range.duration > .zero ? age / word.range.duration.seconds : 1
            drawing.wordProgress = (min(max(progress, 0), 1) * 8).rounded(.down) / 8
        }
        if style == .bounce {
            drawing.wordAge = min((max(age, 0) * 30).rounded(.down) / 30, CaptionRenderer.bounceSeconds)
        }
        return (page, drawing, min(max(since / CaptionRenderer.entranceSeconds, 0), 1))
    }

    /// The page with nothing in motion, as it looks once settled.
    func drawing(for page: CaptionPage, currentWord: Int?) -> CaptionDrawing {
        CaptionDrawing(
            words: page.words.map(\.text),
            keywords: Set(page.words.indices.filter { page.words[$0].isKeyword }),
            currentWord: currentWord,
            lineBreaks: page.lineBreaks,
            emoji: page.emoji,
            translation: settings.translationLanguage == nil ? nil : page.translation
        )
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
    /// How long the spoken word's jump takes, in the Bounce look.
    static let bounceSeconds = 0.3

    private struct Look {
        var fontSize: CGFloat
        /// Core Text weight trait, from -1 (thin) to 1 (black).
        var weight: CGFloat
        var text = white
        var currentWord: CGColor?
        /// Stroke width as a percentage of the font size, drawn behind the letters.
        var outline: CGFloat = 0
        var wordBox: CGColor?
        var backgroundBox: CGColor?
        var shadow = false
        /// The page pops in when it appears.
        var pops = false
        /// The spoken word is drawn a little bigger.
        var currentGrows = false
        /// Words fill with this colour as they are spoken (karaoke).
        var fill: CGColor?
        /// Coloured light around the letters.
        var glow: CGColor?
        var bounces = false
        /// Words appear only once they are spoken.
        var typewriter = false
        /// Letters are drawn as outlines only, except the spoken word.
        var hollow = false
    }

    private static let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    private static let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
    private static let yellow = CGColor(red: 1, green: 0.86, blue: 0.1, alpha: 1)

    /// The colour key words get when no accent is chosen: one that differs from the spoken word's.
    static func keywordColor(for style: CaptionStyle) -> RGBA {
        switch style {
        case .bold, .karaoke: RGBA(0.35, 0.95, 0.45)
        default: .yellow
        }
    }

    /// The style's look with the user's changes (font size, colours).
    private static func look(for settings: CaptionSettings) -> Look {
        var look = look(for: settings.style)
        look.fontSize *= CGFloat(min(max(settings.sizeScale, CaptionSettings.sizeRange.lowerBound), CaptionSettings.sizeRange.upperBound))
        if let text = settings.textColor { look.text = TitleRenderer.cgColor(text) }
        if let accent = settings.accentColor.map(TitleRenderer.cgColor) {
            if look.currentWord != nil { look.currentWord = accent }
            if look.wordBox != nil { look.wordBox = accent }
            if look.fill != nil { look.fill = accent }
            if look.glow != nil { look.glow = accent }
        }
        return look
    }

    private static func look(for style: CaptionStyle) -> Look {
        switch style {
        case .bold:
            return Look(fontSize: 100, weight: 0.62, currentWord: yellow, outline: 24, pops: true, currentGrows: true)
        case .highlight:
            return Look(fontSize: 92, weight: 0.56, outline: 20, wordBox: CGColor(red: 0.16, green: 0.78, blue: 0.36, alpha: 1), pops: true, currentGrows: true)
        case .oneWord:
            return Look(fontSize: 136, weight: 0.62, outline: 22, pops: true)
        case .phrase:
            return Look(fontSize: 104, weight: 0.5, outline: 12, shadow: true, pops: true)
        case .karaoke:
            return Look(fontSize: 84, weight: 0.56, outline: 20, fill: yellow)
        case .glow:
            return Look(fontSize: 96, weight: 0.6, pops: true, glow: CGColor(red: 1, green: 0.3, blue: 0.78, alpha: 1))
        case .bounce:
            return Look(fontSize: 96, weight: 0.62, currentWord: CGColor(red: 0.35, green: 0.85, blue: 1, alpha: 1), outline: 22, bounces: true)
        case .typewriter:
            return Look(fontSize: 72, weight: 0.45, backgroundBox: CGColor(red: 0, green: 0, blue: 0, alpha: 0.55), typewriter: true)
        case .outline:
            return Look(fontSize: 104, weight: 0.72, currentWord: white, outline: 5, shadow: true, pops: true, hollow: true)
        case .classic:
            return Look(fontSize: 54, weight: 0.3, backgroundBox: CGColor(red: 0, green: 0, blue: 0, alpha: 0.7))
        case .minimal:
            return Look(fontSize: 62, weight: 0.4, shadow: true)
        }
    }

    static func animates(_ style: CaptionStyle) -> Bool { look(for: style).pops }
    static func fills(_ style: CaptionStyle) -> Bool { look(for: style).fill != nil }

    /// The page as an image, with `currentWord` emphasised when the style does that.
    static func image(words: [String], currentWord: Int?, style: CaptionStyle) -> CGImage? {
        var settings = CaptionSettings()
        settings.style = style
        return image(CaptionDrawing(words: words, currentWord: currentWord), settings: settings)
    }

    static func image(words: [String], keywords: Set<Int>, currentWord: Int?, emoji: String?, settings: CaptionSettings) -> CGImage? {
        image(CaptionDrawing(words: words, keywords: keywords, currentWord: currentWord, emoji: emoji), settings: settings)
    }

    static func image(_ drawing: CaptionDrawing, settings: CaptionSettings) -> CGImage? {
        let style = settings.style
        var look = look(for: settings)
        let family = settings.fontFamily
        let shown = drawing.words.map { style.isUppercase ? $0.uppercased() : $0 }
        var text = ""
        for (index, word) in shown.enumerated() {
            if index > 0 { text += drawing.lineBreaks.contains(index - 1) ? "\n" : " " }
            text += word
        }
        guard !text.isEmpty else { return nil }
        if look.pops || look.bounces || look.fill != nil, drawing.lineBreaks.isEmpty {
            // The punchy styles read best on one line: shrink a long page a little rather than wrap it.
            let plain = CFAttributedStringCreate(
                nil, text as CFString, [kCTFontAttributeName: makeFont(size: look.fontSize, weight: Double(look.weight), family: family)] as CFDictionary)!
            let kerning = look.wordBox == nil ? 0 : look.fontSize * 0.22 * CGFloat(shown.count - 1)
            let width = CTLineGetTypographicBounds(CTLineCreateWithAttributedString(plain), nil, nil, nil) + kerning + look.fontSize * 0.1
            // The spoken word is drawn a little bigger: leave room for it.
            let needed = look.currentGrows ? width * 1.12 : width
            if needed > maxWidth {
                look.fontSize = max(look.fontSize * maxWidth / needed, look.fontSize * 0.7).rounded(.down)
            }
        }
        let font = makeFont(size: look.fontSize, weight: Double(look.weight), family: family)
        let bigFont = look.currentGrows ? makeFont(size: look.fontSize * 1.12, weight: Double(look.weight), family: family) : font
        let keywordColor = TitleRenderer.cgColor(settings.accentColor ?? keywordColor(for: style))

        // Where each word is in the string, for colouring, boxing, filling and moving it.
        var wordRanges: [CFRange] = []
        var location = 0
        for word in shown {
            let length = (word as NSString).length
            wordRanges.append(CFRange(location: location, length: length))
            location += length + 1
        }
        let currentIndex = drawing.currentWord.flatMap { wordRanges.indices.contains($0) ? $0 : nil }
        let current = style.highlightsCurrentWord ? currentIndex.map { wordRanges[$0] } : nil

        enum Pass { case stroke, fill, solid(CGColor) }
        func attributed(_ pass: Pass) -> CFAttributedString {
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
                    CFAttributedStringSetAttribute(
                        string, CFRange(location: range.location + range.length, length: 1), kCTKernAttributeName, look.fontSize * 0.22 as NSNumber)
                }
            }
            if let current, bigFont !== font {
                CFAttributedStringSetAttribute(string, current, kCTFontAttributeName, bigFont)
            }
            switch pass {
            case .stroke:
                let color = look.hollow ? look.text : black
                CFAttributedStringSetAttribute(string, all, kCTForegroundColorAttributeName, color)
                CFAttributedStringSetAttribute(string, all, kCTStrokeColorAttributeName, color)
                CFAttributedStringSetAttribute(string, all, kCTStrokeWidthAttributeName, look.outline as NSNumber)
            case .fill:
                CFAttributedStringSetAttribute(string, all, kCTForegroundColorAttributeName, look.text)
                if settings.showsKeywords {
                    for index in drawing.keywords where wordRanges.indices.contains(index) {
                        CFAttributedStringSetAttribute(string, wordRanges[index], kCTForegroundColorAttributeName, keywordColor)
                    }
                }
                if let current, let color = look.currentWord {
                    CFAttributedStringSetAttribute(string, current, kCTForegroundColorAttributeName, color)
                }
            case .solid(let color):
                CFAttributedStringSetAttribute(string, all, kCTForegroundColorAttributeName, color)
            }
            return string
        }

        let fill = attributed(.fill)
        let framesetter = CTFramesetterCreateWithAttributedString(fill)
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: 0), nil,
            CGSize(width: maxWidth, height: .greatestFiniteMagnitude), nil
        )
        let textSize = CGSize(width: ceil(suggested.width) + 2, height: ceil(suggested.height) + 2)
        let padding = ceil(look.fontSize * (look.glow == nil ? 0.4 : 0.6))

        // The second language, smaller, under the caption.
        let translationFrame: (framesetter: CTFramesetter, size: CGSize)? = drawing.translation.flatMap { translation in
            let trimmed = translation.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let size = max(look.fontSize * 0.5, 34)
            let attributes: [CFString: Any] = [
                kCTFontAttributeName: makeFont(size: size, weight: 0.4, family: family),
                kCTForegroundColorAttributeName: white,
                kCTParagraphStyleAttributeName: centred(),
            ]
            let setter = CTFramesetterCreateWithAttributedString(CFAttributedStringCreate(nil, trimmed as CFString, attributes as CFDictionary)!)
            let fit = CTFramesetterSuggestFrameSizeWithConstraints(
                setter, CFRange(location: 0, length: 0), nil, CGSize(width: maxWidth, height: .greatestFiniteMagnitude), nil)
            return (setter, CGSize(width: ceil(fit.width) + 2, height: ceil(fit.height) + 2))
        }
        let translationGap: CGFloat = translationFrame == nil ? 0 : ceil(look.fontSize * 0.15)
        let translationHeight = (translationFrame?.size.height ?? 0) + translationGap

        // Room above the text for the emoji.
        let emojiLine: CTLine? =
            settings.showsEmoji
            ? drawing.emoji.map { emoji in
                let emojiFont = CTFontCreateWithName("AppleColorEmoji" as CFString, look.fontSize * 1.05, nil)
                return CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, emoji as CFString, [kCTFontAttributeName: emojiFont] as CFDictionary)!)
            } : nil
        let emojiHeight: CGFloat = emojiLine == nil ? 0 : ceil(look.fontSize * 1.3)
        let width = max(textSize.width, translationFrame?.size.width ?? 0) + padding * 2
        let size = CGSize(width: max(width, emojiHeight * 1.6), height: textSize.height + padding * 2 + emojiHeight + translationHeight)
        let textRect = CGRect(origin: CGPoint(x: (size.width - textSize.width) / 2, y: padding + translationHeight), size: textSize)

        guard
            let context = CGContext(
                data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }
        context.setLineJoin(.round)

        let path = CGPath(rect: textRect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        func passFrame(_ pass: Pass) -> CTFrame {
            CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(attributed(pass)), CFRange(location: 0, length: 0), path, nil)
        }
        let canvas = CGRect(origin: .zero, size: size)
        /// The area of some words, with room around them for outlines and glow, for clipping.
        func area(of indices: some Sequence<Int>, partialLast fraction: Double = 1) -> [CGRect] {
            let list = Array(indices)
            return list.flatMap { index -> [CGRect] in
                let rects = rects(of: wordRanges[index], in: frame, origin: textRect.origin)
                    .map { $0.insetBy(dx: -look.fontSize * 0.1, dy: -look.fontSize * 0.5) }
                guard index == list.last, fraction < 1 else { return rects }
                return rects.map { CGRect(x: $0.minX, y: $0.minY, width: $0.width * fraction, height: $0.height) }
            }
        }

        if let box = look.backgroundBox {
            // For the typewriter, the box grows with the words.
            var rect = textRect
            if look.typewriter, let currentIndex {
                let shown = area(of: 0...currentIndex).reduce(CGRect.null) { $0.union($1) }
                rect = CGRect(x: textRect.minX, y: shown.minY, width: textRect.width, height: textRect.maxY - shown.minY).intersection(textRect)
                if drawing.lineBreaks.isEmpty, (CTFrameGetLines(frame) as! [CTLine]).count == 1 {
                    rect = CGRect(x: textRect.minX, y: textRect.minY, width: shown.maxX - textRect.minX, height: textRect.height)
                }
            }
            let padded = rect.insetBy(dx: -padding * 0.6, dy: -padding * 0.35)
            context.addPath(CGPath(roundedRect: padded, cornerWidth: 14, cornerHeight: 14, transform: nil))
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

        /// The letters, with their outline and shadow.
        func drawLetters() {
            if look.outline > 0 {
                if look.hollow, look.shadow {
                    context.saveGState()
                    context.setShadow(offset: CGSize(width: 0, height: -3), blur: 10, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.9))
                    CTFrameDraw(passFrame(.stroke), context)
                    context.restoreGState()
                } else {
                    CTFrameDraw(passFrame(.stroke), context)
                }
            }
            if look.hollow {
                // Only the spoken word is filled in.
                if let currentIndex {
                    context.saveGState()
                    context.clip(to: area(of: [currentIndex]))
                    CTFrameDraw(passFrame(.solid(look.currentWord ?? look.text)), context)
                    context.restoreGState()
                }
                return
            }
            context.saveGState()
            if look.shadow {
                context.setShadow(offset: CGSize(width: 0, height: -4), blur: 14, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.85))
            }
            if let glow = look.glow {
                context.setShadow(offset: .zero, blur: look.fontSize * 0.3, color: glow)
                CTFrameDraw(frame, context)
            }
            CTFrameDraw(frame, context)
            context.restoreGState()
        }

        context.saveGState()
        if look.typewriter {
            // Only the words said so far, in their final places.
            context.clip(to: area(of: 0...(currentIndex ?? (shown.count - 1))))
        }
        if look.bounces, let currentIndex, drawing.wordAge < bounceSeconds {
            // Everything but the spoken word, then the spoken word lifted.
            let lift = look.fontSize * 0.22 * CGFloat(sin(.pi * drawing.wordAge / bounceSeconds))
            let word = area(of: [currentIndex])
            context.saveGState()
            context.addRect(canvas)
            for rect in word { context.addRect(rect) }
            context.clip(using: .evenOdd)
            drawLetters()
            context.restoreGState()
            context.saveGState()
            context.clip(to: word.map { $0.offsetBy(dx: 0, dy: lift) })
            context.translateBy(x: 0, y: lift)
            drawLetters()
            context.restoreGState()
        } else {
            drawLetters()
        }
        if let fillColor = look.fill, let currentIndex {
            // Karaoke: the words said so far, and part of the one being said, in colour.
            context.saveGState()
            context.clip(to: area(of: 0...currentIndex, partialLast: drawing.wordProgress))
            CTFrameDraw(passFrame(.solid(fillColor)), context)
            context.restoreGState()
        }
        if let glow = look.glow, let currentIndex {
            // The spoken word shines brightest.
            context.saveGState()
            context.clip(to: area(of: [currentIndex]).map { $0.insetBy(dx: -look.fontSize * 0.3, dy: 0) })
            context.setShadow(offset: .zero, blur: look.fontSize * 0.45, color: glow)
            CTFrameDraw(passFrame(.solid(white)), context)
            CTFrameDraw(passFrame(.solid(white)), context)
            context.restoreGState()
        }
        context.restoreGState()

        if let translationFrame {
            let rect = CGRect(
                x: (size.width - translationFrame.size.width) / 2, y: padding, width: translationFrame.size.width, height: translationFrame.size.height)
            let translationPath = CGPath(rect: rect, transform: nil)
            let drawn = CTFramesetterCreateFrame(translationFrame.framesetter, CFRange(location: 0, length: 0), translationPath, nil)
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -3), blur: 10, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.95))
            CTFrameDraw(drawn, context)
            context.restoreGState()
        }
        if let emojiLine {
            let width = CTLineGetTypographicBounds(emojiLine, nil, nil, nil)
            context.setShadow(offset: .zero, blur: 0, color: nil)
            context.textPosition = CGPoint(x: (size.width - width) / 2, y: textRect.maxY + emojiHeight * 0.18)
            CTLineDraw(emojiLine, context)
        }
        return context.makeImage()
    }

    private static func centred() -> CTParagraphStyle {
        var alignment = CTTextAlignment.center
        return withUnsafeMutableBytes(of: &alignment) { pointer in
            var setting = CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: pointer.baseAddress!)
            return CTParagraphStyleCreate(&setting, 1)
        }
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
            result.append(
                CGRect(
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

/// Sample images of each caption look, drawn by the same code as the video, for the look picker.
public enum CaptionPreview {
    public static func image(for style: CaptionStyle) -> CGImage? {
        var settings = CaptionSettings()
        settings.style = style
        return image(for: settings)
    }

    /// A sample with the Short's own caption settings (font, size, colours), a key word and an emoji.
    public static func image(for settings: CaptionSettings) -> CGImage? {
        CaptionRenderer.image(sample(for: settings.style, emoji: "🔥"), settings: settings)
    }

    /// The look's sample caption, caught mid-word so its animation shows.
    static func sample(for style: CaptionStyle, emoji: String? = nil) -> CaptionDrawing {
        switch style {
        case .oneWord:
            return CaptionDrawing(words: ["Wow"], currentWord: 0, emoji: emoji)
        case .phrase:
            return CaptionDrawing(words: ["Make", "it", "pop"], keywords: [2], currentWord: 1, emoji: emoji)
        default:
            return CaptionDrawing(
                words: ["Make", "it", "pop"], keywords: [2], currentWord: 1, emoji: emoji,
                wordProgress: 0.5, wordAge: CaptionRenderer.bounceSeconds / 2)
        }
    }

    /// The look drawn over `frame` (a picture of the Short), scaled to `size`: what the captions
    /// would look like on this Short.
    public static func image(for style: CaptionStyle, settings: CaptionSettings, over frame: CGImage?, size: CGSize) -> CGImage? {
        var settings = settings
        settings.style = style
        guard let caption = CaptionRenderer.image(sample(for: style), settings: settings),
            let context = CGContext(
                data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let bounds = CGRect(origin: .zero, size: size)
        context.setFillColor(CGColor(gray: 0.22, alpha: 1))
        context.fill(bounds)
        if let frame {
            // Fill the chip with the middle of the frame.
            let scale = max(size.width / CGFloat(frame.width), size.height / CGFloat(frame.height))
            let drawn = CGSize(width: CGFloat(frame.width) * scale, height: CGFloat(frame.height) * scale)
            context.draw(frame, in: CGRect(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2, width: drawn.width, height: drawn.height))
        }
        let fit = min(size.width * 0.94 / CGFloat(caption.width), size.height * 0.9 / CGFloat(caption.height))
        let drawn = CGSize(width: CGFloat(caption.width) * fit, height: CGFloat(caption.height) * fit)
        context.draw(caption, in: CGRect(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2, width: drawn.width, height: drawn.height))
        return context.makeImage()
    }

    /// Where the caption on screen at `time` is (canvas pixels, origin top left), for dragging it.
    public static func frame(in project: Project, at time: CMTime) -> CGRect? {
        let track = CaptionTrack(project: project)
        guard let state = track.state(at: time),
            let image = CaptionRenderer.image(track.drawing(for: state.page, currentWord: nil), settings: track.settings)
        else { return nil }
        let size = CGSize(width: image.width, height: image.height)
        return CGRect(x: (Project.canvasSize.width - size.width) / 2, y: track.top(forHeight: size.height), width: size.width, height: size.height)
    }
}
