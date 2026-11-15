@preconcurrency import AVFoundation
import EditorCore
import Testing

@testable import RenderEngine

private let red: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 255, 255)
private let blue: (UInt8, UInt8, UInt8, UInt8) = (255, 0, 0, 255)

@MainActor
struct TextRenderTests {
    private func frame(of built: PlayableComposition, at seconds: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: built.composition)
        generator.videoComposition = built.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }

    private func isRed(_ p: (r: UInt8, g: UInt8, b: UInt8)) -> Bool { p.r > 200 && p.g < 60 && p.b < 60 }
    private func isBlue(_ p: (r: UInt8, g: UInt8, b: UInt8)) -> Bool { p.b > 200 && p.r < 60 && p.g < 60 }

    private func oneClip(_ url: URL) async throws -> Project {
        var project = Project()
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(url)))
        return project
    }

    /// How many pixels of `image` are close to `color` (r, g, b).
    private func count(_ image: CGImage, near color: (Int, Int, Int)) -> Int {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 0, to: data.count, by: 4).count {
            data[$0 + 3] > 200 && abs(Int(data[$0]) - color.0) < 40 && abs(Int(data[$0 + 1]) - color.1) < 40 && abs(Int(data[$0 + 2]) - color.2) < 40
        }
    }

    // MARK: Text

    @Test func aTitleIsDrawnInItsOwnLook() async throws {
        let url = try await Fixture.video(width: 180, height: 320, bgra: blue)
        var project = try await oneClip(url)
        let id = project.addTitle(at: .zero, text: "Look at this")
        project.updateTitle(id) { title in
            title.entrance = .none
            title.look.boxColor = RGBA(1, 0, 0)
            title.look.boxPerLine = false
            title.look.textColor = .white
            title.horizontalPosition = 0.2
        }
        let box = try #require(TitlePreview.frame(of: project.titles[0]))
        #expect(box.minX < 20) // pushed to the left edge, but kept on the canvas
        let image = try await frame(of: CompositionBuilder.build(project), at: 0.5)
        #expect(isRed(Fixture.pixel(image, x: Int(box.minX) + 6, y: Int(box.midY))))
    }

    @Test func typingShowsMoreLettersOverTime() async throws {
        var look = TitleStyle.bold.look
        look.outlineColor = nil
        let few = try #require(TitleRenderer.image(text: "Typing here", look: look, visibleCharacters: 2))
        let all = try #require(TitleRenderer.image(text: "Typing here", look: look))
        #expect(few.width == all.width)
        #expect(count(few, near: (255, 255, 255)) * 3 < count(all, near: (255, 255, 255)))
    }

    @Test func keyWordsAreInTheAccentColourAndEmojiGoAbove() throws {
        var settings = CaptionSettings()
        settings.style = .minimal
        settings.accentColor = RGBA(1, 0, 0)
        let plain = try #require(CaptionRenderer.image(words: ["make", "money"], keywords: [], currentWord: nil, emoji: nil, settings: settings))
        let keyword = try #require(CaptionRenderer.image(words: ["make", "money"], keywords: [1], currentWord: nil, emoji: nil, settings: settings))
        #expect(count(plain, near: (255, 0, 0)) < 20)
        #expect(count(keyword, near: (255, 0, 0)) > 200)
        let withEmoji = try #require(CaptionRenderer.image(words: ["make", "money"], keywords: [], currentWord: nil, emoji: "💰", settings: settings))
        #expect(withEmoji.height > plain.height)
        settings.sizeScale = 1.5
        let bigger = try #require(CaptionRenderer.image(words: ["make", "money"], keywords: [], currentWord: nil, emoji: nil, settings: settings))
        #expect(bigger.height > plain.height)
    }
}
