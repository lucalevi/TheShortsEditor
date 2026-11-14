import AppKit
import CoreText
import EditorCore
import Synchronization

/// Draws stickers: an emoji with Core Text (in colour), or an SF Symbol in its colour with a soft
/// dark shadow so it stands out on any picture. Thread-safe: the video compositor calls it.
nonisolated enum StickerRenderer {
    private static let cache = Mutex<[Sticker: CGImage]>([:])

    static func image(_ sticker: Sticker) -> CGImage? {
        if let cached = cache.withLock({ $0[sticker] }) { return cached }
        let made: CGImage?
        switch sticker.kind {
        case .emoji(let emoji): made = emojiImage(emoji, size: CGFloat(sticker.size))
        case .symbol(let name): made = symbolImage(name, color: sticker.color, size: CGFloat(sticker.size))
        }
        if let made {
            cache.withLock { cache in
                if cache.count > 80 { cache.removeAll() }
                cache[sticker] = made
            }
        }
        return made
    }

    private static func context(_ side: Int) -> CGContext? {
        CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    private static func emojiImage(_ emoji: String, size: CGFloat) -> CGImage? {
        let side = Int(ceil(size * 1.15))
        guard let context = context(side) else { return nil }
        let font = CTFontCreateWithName("AppleColorEmoji" as CFString, size * 0.82, nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: emoji, attributes: [.font: font]))
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        context.textPosition = CGPoint(x: (CGFloat(side) - bounds.width) / 2 - bounds.minX, y: (CGFloat(side) - bounds.height) / 2 - bounds.minY)
        CTLineDraw(line, context)
        return context.makeImage()
    }

    private static func symbolImage(_ name: String, color: RGBA, size: CGFloat) -> CGImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: size * 0.7, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)]))
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { return nil }
        let side = Int(ceil(size * 1.15))
        guard let context = context(side) else { return nil }
        let symbolSize = symbol.size
        let scale = size / max(symbolSize.width, symbolSize.height, 1)
        let drawn = CGSize(width: symbolSize.width * scale, height: symbolSize.height * scale)
        let rect = CGRect(x: (CGFloat(side) - drawn.width) / 2, y: (CGFloat(side) - drawn.height) / 2, width: drawn.width, height: drawn.height)
        context.setShadow(offset: CGSize(width: 0, height: -size * 0.02), blur: size * 0.08, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.6))
        // Drawn as shapes, so it stays sharp at any size.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        symbol.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}
