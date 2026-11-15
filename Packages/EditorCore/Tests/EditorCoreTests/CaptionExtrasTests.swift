import CoreGraphics
import CoreMedia
import Foundation
import Testing

@testable import EditorCore

private func seconds(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600).snappedToFrame() }

private func video(_ name: String = "talk.mov", seconds: Int64 = 10, size: CGSize = CGSize(width: 1080, height: 1920), audio: Bool = true) -> MediaAsset {
    MediaAsset(url: URL(fileURLWithPath: "/tmp/\(name)"), name: name, duration: CMTime(value: seconds, timescale: 1), displaySize: size, hasAudio: audio)
}

private func sound(_ name: String = "pop.m4a", seconds: Double = 1) -> MediaAsset {
    MediaAsset(
        url: URL(fileURLWithPath: "/tmp/\(name)"), name: name, duration: CMTime(seconds: seconds, preferredTimescale: 600), displaySize: .zero, hasAudio: true,
        hasVideo: false)
}

/// One 10 s video with a transcript: a word every second ("w0" … "w9"), each half a second long.
private func talking(words: [String]? = nil) -> (Project, MediaAsset.ID) {
    var p = Project()
    let id = p.addAsset(video())
    p.appendClip(of: id)
    let texts = words ?? (0..<10).map { "w\($0)" }
    p.transcripts[id] = Transcript(
        language: .english,
        words: texts.enumerated().map { index, text in
            Word(text: text, start: seconds(Double(index)), duration: seconds(0.5))
        })
    return (p, id)
}

struct CaptionExtrasTests {
    @Test func numbersAndLongWordsAreKeyWords() {
        let words = ["I", "made", "5000", "dollars", "with", "this", "simple", "trick", "and", "everyone", "was", "absolutely", "amazed"]
            .enumerated().map { Word(text: $1, start: seconds(Double($0)), duration: seconds(0.5)) }
        let picked = Keywords.pick(from: words)
        let texts = words.filter { picked.contains($0.id) }.map(\.text)
        #expect(texts.contains("5000"))
        #expect(texts.contains("absolutely"))
        #expect(!texts.contains("everyone"))
    }

    @Test func smallWordsAreNeverKeyWords() {
        let words = ["and", "the", "so", "um"].map { Word(text: $0, start: .zero, duration: seconds(0.2)) }
        #expect(Keywords.pick(from: words).isEmpty)
    }

    @Test func pickingMarksTheTranscripts() {
        var (p, id) = talking(words: ["Today", "we", "talk", "about", "1000", "followers"])
        let count = p.pickKeywords()
        #expect(count >= 1)
        #expect(p.transcripts[id]?.words.first { $0.text == "1000" }?.isKeyword == true)
        #expect(CaptionLayout.timelineWords(in: p).first { $0.text == "1000" }?.isKeyword == true)
    }

    @Test func emojiMatchWordsInEveryLanguage() {
        #expect(EmojiSuggestions.emoji(for: "money!") == "💰")
        #expect(EmojiSuggestions.emoji(for: "Soldi") == "💰")
        #expect(EmojiSuggestions.emoji(for: "Geld") == "💰")
        #expect(EmojiSuggestions.emoji(for: "argent") == "💰")
        #expect(EmojiSuggestions.emoji(for: "cars") == "🚗")
        #expect(EmojiSuggestions.emoji(for: "careful") == "⚠️")
        #expect(EmojiSuggestions.emoji(for: "card") == nil)
        #expect(EmojiSuggestions.emoji(for: "the") == nil)
    }

    @Test func atMostOneEmojiPerCaption() {
        var (p, _) = talking(words: ["money", "love", "fire", "coffee"])
        p.captions.style = .classic
        p.suggestEmoji()
        let pages = CaptionLayout.pages(in: p)
        for page in pages { #expect(page.words.compactMap(\.emoji).count <= 1) }
        #expect(pages.first?.emoji == "💰")
    }

    @Test func captionSettingsFromOlderFilesOpen() throws {
        let json = #"{"isVisible":true,"style":"highlight","verticalPosition":0.5}"#
        let settings = try JSONDecoder().decode(CaptionSettings.self, from: Data(json.utf8))
        #expect(settings.style == .highlight && settings.sizeScale == 1 && settings.showsEmoji && !settings.isCustomized)
    }
}
