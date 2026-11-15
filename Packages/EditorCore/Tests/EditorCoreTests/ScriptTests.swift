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

struct ScriptTests {
    @Test func fillerSoundsAreFound() {
        let (p, _) = talking(words: ["So", "um", "this", "is", "eh", "great"])
        let found = Set(p.fillerAndRepeatedWords().map(\.wordID))
        let texts = p.script.filter { found.contains($0.wordID) }.map(\.text)
        #expect(texts == ["um", "eh"])
    }

    @Test func wordsSaidTwiceKeepTheSecondTime() {
        let (p, _) = talking(words: ["I", "I", "think", "it", "works", "it", "works"])
        let found = p.fillerAndRepeatedWords().map(\.wordID)
        let words = p.script
        #expect(found == [words[0].wordID, words[3].wordID, words[4].wordID])
    }

    @Test func numbersSaidTwiceAreNotRepeats() {
        let (p, _) = talking(words: ["it", "was", "20", "20"])
        #expect(p.fillerAndRepeatedWords().isEmpty)
    }

    @Test func cuttingAWordRemovesItAndThePauseAfter() {
        var (p, _) = talking()
        let w3 = p.script[3]
        let plan = p.cutPlan(removing: [w3.ref])
        #expect(plan.timelineCuts == [CMTimeRange(start: seconds(3), end: seconds(4))])
        p.apply(plan)
        #expect(p.duration == seconds(9))
        #expect(!p.script.contains { $0.text == "w3" })
        #expect(p.script.contains { $0.text == "w4" })
    }

    @Test func cuttingNeighboursMakesOneCut() {
        let (p, _) = talking()
        let words = p.script
        let plan = p.cutPlan(removing: [words[2].ref, words[3].ref])
        #expect(plan.timelineCuts == [CMTimeRange(start: seconds(2), end: seconds(4))])
    }

    @Test func theLastWordIsCutToItsEnd() {
        let (p, _) = talking()
        let plan = p.cutPlan(removing: [p.script[9].ref])
        #expect(plan.timelineCuts == [CMTimeRange(start: seconds(9), end: seconds(9.5))])
    }

    @Test func wordsCanBeChanged() {
        var (p, _) = talking()
        let id = p.script[2].wordID
        p.updateWords([id]) { $0.isKeyword = true }
        #expect(p.script[2].isKeyword)
    }
}
