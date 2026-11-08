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
