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

struct TitleLookTests {
    @Test func aNewTitleLooksLikeItsStyle() {
        let title = TextOverlay(text: "Hi", style: .marker, start: .zero, duration: seconds(1))
        #expect(title.look == TitleStyle.marker.look)
        #expect(!title.isCustomized)
        #expect(title.horizontalPosition == 0.5)
    }

    @Test func changingStyleKeepsTheFont() {
        var title = TextOverlay(text: "Hi", start: .zero, duration: seconds(1))
        title.look.fontFamily = "EB Garamond"
        title.look.size = 150
        title.applyStyle(.dark)
        #expect(title.look.fontFamily == "EB Garamond")
        #expect(title.look.size == TitleStyle.dark.look.size)
        #expect(title.isCustomized)
    }

    @Test func titlesSavedBeforeLooksStillOpen() throws {
        let json = """
            {"id":"\(UUID())","text":"Hook","style":"label","entrance":"pop","start":{"value":0,"timescale":1},"duration":{"value":3,"timescale":1},"verticalPosition":0.24}
            """
        let title = try JSONDecoder().decode(TextOverlay.self, from: Data(json.utf8))
        #expect(title.look == TitleStyle.label.look)
        #expect(title.horizontalPosition == 0.5)
    }

    @Test func savedStylesAreCodable() throws {
        let style = SavedTextStyle(name: "Brand", look: TextLook(fontFamily: "Avenir", textColor: .yellow), entrance: .typewriter)
        let decoded = try JSONDecoder().decode(SavedTextStyle.self, from: JSONEncoder().encode(style))
        #expect(decoded == style)
    }
}
