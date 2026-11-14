import CoreMedia
import Foundation
import Testing

@testable import EditorCore

private func seconds(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600) }

/// A project with one 10-second file on the timeline, whose words are given as (text, start, length).
private func project(_ words: [(String, Double, Double)]) -> Project {
    var project = Project()
    let asset = MediaAsset(
        url: URL(fileURLWithPath: "/tmp/a.mov"), name: "a", duration: seconds(10),
        displaySize: CGSize(width: 1080, height: 1920), hasAudio: true)
    project.addAsset(asset)
    project.appendClip(of: asset.id)
    project.transcripts[asset.id] = Transcript(
        language: .english,
        words: words.map {
            Word(text: $0.0, start: seconds($0.1), duration: seconds($0.2))
        })
    return project
}

struct CaptionTests {
    @Test func wordsFollowTheClipsAfterAnEdit() {
        var p = project([("one", 1, 0.5), ("two", 4, 0.5), ("three", 7, 0.5)])
        p.timeline.split(at: seconds(3))
        p.timeline.split(at: seconds(6))
        // Delete the middle part ("two"), then the last part plays from 3 s.
        p.timeline.remove(p.timeline.clips[1].id)
        let words = CaptionLayout.timelineWords(in: p)
        #expect(words.map(\.text) == ["one", "three"])
        #expect(words[1].range.start == seconds(4))
    }

    @Test func aWordCutInHalfGoesWithItsMiddle() {
        var p = project([("hello", 2.8, 0.6)]) // middle at 3.1 s
        p.timeline.split(at: seconds(3))
        let words = CaptionLayout.timelineWords(in: p)
        #expect(words.count == 1)
        #expect(words[0].clipID == p.timeline.clips[1].id)
        // Cut to the clip it plays in.
        #expect(words[0].range.start == seconds(3))
    }

    @Test func pagesBreakAtPausesSentencesAndLength() {
        let p = project([
            ("so", 0, 0.2), ("this", 0.2, 0.2), ("is", 0.4, 0.2), ("it.", 0.6, 0.2),
            ("next", 0.8, 0.2), ("thing", 1.0, 0.2),
            ("later", 3.0, 0.3),
        ])
        let pages = CaptionLayout.pages(in: p, style: .classic)
        #expect(pages.map(\.text) == ["so this is it.", "next thing", "later"])

        let bold = CaptionLayout.pages(in: p, style: .bold)
        #expect(bold.allSatisfy { $0.text.count <= CaptionStyle.bold.maxCharacters })

        let single = CaptionLayout.pages(in: p, style: .oneWord)
        #expect(single.count == 7)
    }

    @Test func pagesNeverCrossACut() {
        var p = project([("left", 2.6, 0.2), ("right", 3.1, 0.2)])
        p.timeline.split(at: seconds(3))
        #expect(CaptionLayout.pages(in: p, style: .classic).count == 2)
    }

    @Test func pagesLingerButNotOverTheNextOne() throws {
        let p = project([("a", 1, 0.5), ("b", 1.8, 0.5)])
        let pages = CaptionLayout.pages(in: p, style: .oneWord)
        #expect(pages[0].range.end == seconds(1.8))
        #expect(pages[1].range.end == seconds(2.8))
        let shown = try #require(CaptionLayout.page(at: seconds(1.6), in: pages))
        #expect(shown.text == "a")
        #expect(CaptionLayout.page(at: seconds(5), in: pages) == nil)
    }

    @Test func jumpingToAPageLandsOnIt() throws {
        let p = project([("a", 1, 0.8), ("b", 1.81, 0.5)])
        let pages = CaptionLayout.pages(in: p, style: .oneWord)
        let frame = pages[1].firstFrame
        #expect(frame.timescale == Project.frameRate)
        #expect(CaptionLayout.page(at: frame, in: pages)?.text == "b")
    }

    @Test func currentWordIsTheLastOneStarted() {
        let p = project([("a", 1, 0.2), ("b", 1.5, 0.2), ("c", 2, 0.2)])
        let page = CaptionLayout.pages(in: p, style: .classic)[0]
        #expect(page.wordIndex(at: seconds(1.1)) == 0)
        #expect(page.wordIndex(at: seconds(1.8)) == 1)
        #expect(page.wordIndex(at: seconds(2.1)) == 2)
    }

    @Test func fixingAWordKeepsItsTiming() throws {
        var p = project([("helo", 1, 0.5), ("word", 1.5, 0.5)])
        let page = CaptionLayout.pages(in: p, style: .classic)[0]
        p.replaceWords(page.words.map(\.wordID), in: page.assetID, with: "hello world")
        let words = try #require(p.transcripts[page.assetID]?.words)
        #expect(words.map(\.text) == ["hello", "world"])
        #expect(words[1].start == seconds(1.5))
    }

    @Test func changingTheNumberOfWordsSharesTheTime() throws {
        var p = project([("gonna", 1, 1), ("after", 3, 1)])
        let first = CaptionLayout.pages(in: p, style: .oneWord)[0]
        p.replaceWords(first.words.map(\.wordID), in: first.assetID, with: "going to")
        let words = try #require(p.transcripts[first.assetID]?.words)
        #expect(words.map(\.text) == ["going", "to", "after"])
        #expect(words[0].start == seconds(1))
        #expect(words[1].end == seconds(2))
        #expect(words[0].duration > words[1].duration)

        p.replaceWords([words[2].id], in: first.assetID, with: "  ")
        #expect(p.transcripts[first.assetID]?.words.count == 2)
    }

    @Test func onlyUntranscribedFilesNeedWork() {
        var p = project([("hi", 0, 0.2)])
        #expect(p.assetsNeedingTranscription(in: .english).isEmpty)
        #expect(p.assetsNeedingTranscription(in: .italian).count == 1)
        p.timeline.split(at: seconds(5))
        #expect(p.assetsNeedingTranscription(in: .german).count == 1)
        #expect(p.hasCaptions)
    }

    @Test func transcriptsSurviveSaving() throws {
        let p = project([("ciao", 0.5, 0.25)])
        let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(p))
        #expect(decoded == p)
    }

    @Test func captionPositionStaysClearOfYouTubesButtons() {
        let range = SafeZone.captionRange
        #expect(range.lowerBound * 1920 > Double(SafeZone.top))
        #expect(range.upperBound * 1920 < 1920 - Double(SafeZone.bottom))
        #expect(CaptionPlacement.allCases.allSatisfy { range.contains($0.verticalPosition) })
        #expect(CaptionPlacement(CaptionSettings().verticalPosition) == .bottom)
    }
}
