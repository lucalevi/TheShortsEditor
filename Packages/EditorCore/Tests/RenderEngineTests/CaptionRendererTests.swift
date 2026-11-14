import CoreGraphics
import EditorCore
import Testing

@testable import RenderEngine

@MainActor
struct CaptionRendererTests {
    @Test func punchyStylesFitLongPagesOnOneLine() throws {
        let short = try #require(CaptionRenderer.image(words: ["Hey"], currentWord: 0, style: .bold))
        let long = try #require(CaptionRenderer.image(words: ["Hey", "everyone,"], currentWord: 0, style: .bold))
        #expect(long.height <= short.height)
        #expect(CGFloat(long.width) <= CaptionRenderer.maxWidth + 100)
    }

    @Test func subtitlesWrapOntoMoreLines() throws {
        let one = try #require(CaptionRenderer.image(words: ["Short"], currentWord: nil, style: .classic))
        let words = "this sentence is much too long to fit on a single line".split(separator: " ").map(String.init)
        let many = try #require(CaptionRenderer.image(words: words, currentWord: nil, style: .classic))
        #expect(many.height > one.height)
    }

    @Test func emptyPageDrawsNothing() {
        #expect(CaptionRenderer.image(words: [], currentWord: nil, style: .bold) == nil)
    }
}

/// Reads an image's pixels (RGBA, premultiplied, top row first).
@MainActor
private struct Pixels {
    let width: Int, height: Int
    let data: [UInt8]

    init(_ image: CGImage) {
        width = image.width
        height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        self.data = data
    }

    /// Pixels that are clearly coloured (not white, grey or black) and visible.
    var colourful: Int {
        stride(from: 0, to: data.count, by: 4).filter { i in
            let r = Int(data[i]), g = Int(data[i + 1]), b = Int(data[i + 2]), a = Int(data[i + 3])
            return a > 128 && max(r, g, b) - min(r, g, b) > 80
        }.count
    }

    var visible: Int { stride(from: 3, to: data.count, by: 4).filter { data[$0] > 128 }.count }

    /// The visible pixels in the left `fraction` of the image.
    func visible(leftOf fraction: Double) -> Int {
        let limit = Int(Double(width) * fraction)
        var count = 0
        for y in 0..<height { for x in 0..<limit where data[(y * width + x) * 4 + 3] > 128 { count += 1 } }
        return count
    }

    /// The lowest row (from the top) with a visible pixel.
    var lowestRow: Int {
        for y in stride(from: height - 1, through: 0, by: -1) {
            for x in 0..<width where data[(y * width + x) * 4 + 3] > 128 { return y }
        }
        return 0
    }
}

@MainActor
struct CaptionLookTests {
    private func settings(_ style: CaptionStyle) -> CaptionSettings {
        var settings = CaptionSettings()
        settings.style = style
        return settings
    }

    @Test(arguments: CaptionStyle.allCases)
    func everyLookDraws(_ style: CaptionStyle) throws {
        let image = try #require(CaptionRenderer.image(CaptionDrawing(words: ["Make", "it", "pop"], currentWord: 1), settings: settings(style)))
        #expect(Pixels(image).visible > 1000)
        #expect(CGFloat(image.width) <= CaptionRenderer.maxWidth + 200)
    }

    @Test func karaokeFillsAsTheWordIsSaid() throws {
        let words = ["hello", "world"]
        let start = try #require(CaptionRenderer.image(CaptionDrawing(words: words, currentWord: 0, wordProgress: 0), settings: settings(.karaoke)))
        let half = try #require(CaptionRenderer.image(CaptionDrawing(words: words, currentWord: 0, wordProgress: 0.5), settings: settings(.karaoke)))
        let later = try #require(CaptionRenderer.image(CaptionDrawing(words: words, currentWord: 1, wordProgress: 1), settings: settings(.karaoke)))
        #expect(Pixels(start).colourful < 50)
        #expect(Pixels(half).colourful > Pixels(start).colourful + 200)
        #expect(Pixels(later).colourful > Pixels(half).colourful * 2)
    }

    @Test func typewriterShowsOnlyTheWordsSaidSoFar() throws {
        let words = ["one", "two", "three", "four"]
        let first = try #require(CaptionRenderer.image(CaptionDrawing(words: words, currentWord: 0), settings: settings(.typewriter)))
        let all = try #require(CaptionRenderer.image(CaptionDrawing(words: words, currentWord: 3), settings: settings(.typewriter)))
        #expect(first.width == all.width && first.height == all.height) // nothing moves as words appear
        #expect(Pixels(first).visible < Pixels(all).visible / 2)
    }

    @Test func bounceLiftsTheSpokenWord() throws {
        let still = try #require(CaptionRenderer.image(CaptionDrawing(words: ["up", "here"], currentWord: 0, wordAge: 1), settings: settings(.bounce)))
        let jumping = try #require(
            CaptionRenderer.image(
                CaptionDrawing(words: ["up", "here"], currentWord: 0, wordAge: CaptionRenderer.bounceSeconds / 2), settings: settings(.bounce)))
        #expect(still.width == jumping.width && still.height == jumping.height)
        #expect(Pixels(still).data != Pixels(jumping).data)
    }

    @Test func outlineFillsOnlyTheSpokenWord() throws {
        let image = try #require(CaptionRenderer.image(CaptionDrawing(words: ["hollow", "letters"], currentWord: 0), settings: settings(.outline)))
        let pixels = Pixels(image)
        // The filled word ("HOLLOW", on the left) has far more ink than the hollow one.
        let left = pixels.visible(leftOf: 0.5)
        #expect(left > (pixels.visible - left) * 2)
    }

    @Test func emojiTypedInACaptionAreInColour() throws {
        let plain = try #require(CaptionRenderer.image(CaptionDrawing(words: ["great", "job"]), settings: settings(.classic)))
        let withEmoji = try #require(CaptionRenderer.image(CaptionDrawing(words: ["great", "job", "🎉"]), settings: settings(.classic)))
        #expect(Pixels(plain).colourful < 20)
        #expect(Pixels(withEmoji).colourful > 300)
        // Also under the black outline of the bold looks.
        let bold = try #require(CaptionRenderer.image(CaptionDrawing(words: ["wow", "🔥"]), settings: settings(.phrase)))
        #expect(Pixels(bold).colourful > 300)
    }

    @Test func lineBreaksAndTranslationsAddLines() throws {
        let one = try #require(CaptionRenderer.image(CaptionDrawing(words: ["two", "lines"]), settings: settings(.phrase)))
        let two = try #require(CaptionRenderer.image(CaptionDrawing(words: ["two", "lines"], lineBreaks: [0]), settings: settings(.phrase)))
        #expect(two.height > one.height + 60)
        let translated = try #require(CaptionRenderer.image(CaptionDrawing(words: ["two", "lines"], translation: "due righe"), settings: settings(.phrase)))
        #expect(translated.height > one.height + 30)
    }

    @Test func previewsDrawOverTheShortsFrame() throws {
        let red = try #require(
            CGContext(
                data: nil, width: 108, height: 192, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        red.setFillColor(CGColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1))
        red.fill(CGRect(x: 0, y: 0, width: 108, height: 192))
        let chip = try #require(CaptionPreview.image(for: .glow, settings: CaptionSettings(), over: red.makeImage(), size: CGSize(width: 160, height: 80)))
        #expect(chip.width == 160)
        #expect(Pixels(chip).colourful > 3000) // mostly the red frame
    }
}
