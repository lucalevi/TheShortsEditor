import CoreMedia
import Foundation
import Testing
@testable import EditorCore

private func seconds(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600) }

private func asset(_ name: String, length: Double = 10, video: Bool = true) -> MediaAsset {
    MediaAsset(url: URL(fileURLWithPath: "/tmp/\(name).mov"), name: name, duration: seconds(length),
               displaySize: video ? CGSize(width: 1080, height: 1920) : .zero, hasAudio: true, hasVideo: video)
}

private func transcript(_ words: [(String, Double, Double)]) -> Transcript {
    Transcript(language: .english, words: words.map { Word(text: $0.0, start: seconds($0.1), duration: seconds($0.2)) })
}

/// One 10-second clip on the timeline, with words.
private func project(_ words: [(String, Double, Double)]) -> Project {
    var p = Project()
    let a = asset("main")
    p.addAsset(a)
    p.appendClip(of: a.id)
    p.transcripts[a.id] = transcript(words)
    return p
}

struct CaptionSourcesTests {
    @Test func voiceOverWordsBecomeCaptions() throws {
        var p = project([])
        p.transcripts = [:]
        let voice = asset("voice", length: 5, video: false)
        p.addAsset(voice)
        let made = p.addSound(of: voice.id, at: seconds(2), isVoiceOver: true)
        let id = try #require(made)
        p.transcripts[voice.id] = transcript([("hello", 0.5, 0.4), ("there", 1, 0.4)])
        let words = CaptionLayout.timelineWords(in: p)
        #expect(words.map(\.text) == ["hello", "there"])
        #expect(words[0].range.start == seconds(2.5))
        #expect(words[0].source == .sound)
        #expect(words[0].clipID == id)
        #expect(p.hasCaptions)
    }

    @Test func voiceOverWinsWhereBothTalk() throws {
        var p = project([("clip", 1, 0.5), ("talk", 4, 0.5)])
        let voice = asset("voice", length: 2, video: false)
        p.addAsset(voice)
        let made = p.addSound(of: voice.id, at: seconds(3.5), isVoiceOver: true)
        try #require(made != nil)
        p.transcripts[voice.id] = transcript([("over", 0.4, 0.4)])  // 3.9–4.3 s, over "talk"
        #expect(CaptionLayout.timelineWords(in: p).map(\.text) == ["clip", "over"])
    }

    @Test func brollWithSoundOnHasCaptionsMutedDoesNot() throws {
        var p = project([])
        let broll = asset("broll", length: 3)
        p.addAsset(broll)
        let made = p.addOverlay(of: broll.id, at: seconds(1))
        let id = try #require(made)
        p.transcripts[broll.id] = transcript([("look", 0.5, 0.5)])
        #expect(CaptionLayout.timelineWords(in: p).isEmpty)
        #expect(!p.assetsNeedingTranscription(in: .english).contains { $0.id == broll.id })
        p.updateOverlay(id) { $0.clip.isMuted = false }
        let words = CaptionLayout.timelineWords(in: p)
        #expect(words.map(\.text) == ["look"])
        #expect(words[0].source == .broll)
        #expect(words[0].range.start == seconds(1.5))
    }

    @Test func mutedClipsHaveNoCaptionsUnlessTyped() {
        var p = project([("hi", 1, 0.5)])
        p.timeline.clips[0].isMuted = true
        #expect(!p.hasCaptions)
        p.transcripts[p.timeline.clips[0].assetID]?.isTyped = true
        #expect(p.hasCaptions)
    }

    @Test func voiceOversAreTranscribedFirst() throws {
        var p = project([])
        p.transcripts = [:]
        let voice = asset("voice", length: 5, video: false)
        p.addAsset(voice)
        let made = p.addSound(of: voice.id, at: .zero, isVoiceOver: true)
        try #require(made != nil)
        let needed = p.assetsNeedingTranscription(in: .english)
        #expect(needed.map(\.name) == ["voice", "main"])
    }

    @Test func builtInSoundEffectsAreNeverTranscribed() throws {
        var p = project([])
        let effect = MediaAsset(url: URL(fileURLWithPath: "/Users/x/Library/Application Support/Shorts Editor/Sound Effects/whoosh.m4a"),
                                name: "Whoosh", duration: seconds(1), displaySize: .zero, hasAudio: true, hasVideo: false)
        p.addAsset(effect)
        let made = p.addSound(of: effect.id, at: .zero)
        try #require(made != nil)
        #expect(!p.assetsNeedingTranscription(in: .italian).contains { $0.id == effect.id })
    }
}

struct CaptionTextEditingTests {
    private let five: [(String, Double, Double)] = [("one", 0, 0.4), ("two", 0.5, 0.4), ("three", 1, 0.4), ("four", 1.5, 0.4), ("five", 2, 0.4)]

    @Test func tokensRememberNewLines() {
        let tokens = CaptionText.tokens("Hello  big\nworld ")
        #expect(tokens.map(\.text) == ["Hello", "big", "world"])
        #expect(tokens.map(\.lineBreakAfter) == [false, true, false])
        #expect(CaptionText.string(tokens) == "Hello big\nworld")
    }

    @Test func returnSplitsACaptionAtTheCursor() throws {
        var p = project(five)
        let page = CaptionLayout.pages(in: p, style: .classic)[0]
        #expect(page.text == "one two three four five")
        let text = page.text
        let newFirst = p.splitCaption(page.words.map(\.wordID), in: page.assetID, text: text, at: "one two".count)
        #expect(newFirst != nil)
        let pages = CaptionLayout.pages(in: p, style: .classic)
        #expect(pages.map(\.text) == ["one two", "three four five"])
        // Timing is kept when the words are the same.
        #expect(pages[1].words[0].range.start == seconds(1))
    }

    @Test func splittingInsideAWordSplitsTheWord() {
        var p = project([("hello", 0, 1)])
        let page = CaptionLayout.pages(in: p)[0]
        p.splitCaption(page.words.map(\.wordID), in: page.assetID, text: "hello", at: 2)
        #expect(CaptionLayout.pages(in: p).map(\.text) == ["he", "llo"])
    }

    @Test func splittingAtTheEndOnlySavesTheText() {
        var p = project(five)
        let page = CaptionLayout.pages(in: p, style: .classic)[0]
        let result = p.splitCaption(page.words.map(\.wordID), in: page.assetID, text: "one two three four six", at: 22)
        #expect(result == nil)
        #expect(CaptionLayout.pages(in: p, style: .classic).map(\.text) == ["one two three four six"])
    }

    @Test func splittingKeepsTheNextCaptionAsItWas() {
        // Bold holds 16 characters: "one two three" / "four five".
        var p = project(five)
        let before = CaptionLayout.pages(in: p, style: .bold).map(\.text)
        #expect(before == ["one two three", "four five"])
        let page = CaptionLayout.pages(in: p, style: .bold)[0]
        p.splitCaption(page.words.map(\.wordID), in: page.assetID, text: page.text, at: 3)
        // "two three four" would fit, but "four five" stays its own caption.
        #expect(CaptionLayout.pages(in: p, style: .bold).map(\.text) == ["one", "two three", "four five"])
    }

    @Test func backspaceAtTheStartMergesWithTheCaptionBefore() {
        var p = project(five)
        let pages = CaptionLayout.pages(in: p, style: .bold)
        #expect(pages.count == 2)
        p.mergeCaptionWithPrevious(pages[1].words.map(\.wordID), in: pages[1].assetID, text: pages[1].text)
        #expect(CaptionLayout.pages(in: p, style: .bold).map(\.text) == ["one two three four five"])
    }

    @Test func editedCaptionsKeepTheirShapeInOtherLooks() {
        // Bold: "one two three" / "four five". Split the first, join "four five" back onto "three".
        var p = project(five)
        var pages = CaptionLayout.pages(in: p, style: .bold)
        p.splitCaption(pages[0].words.map(\.wordID), in: pages[0].assetID, text: pages[0].text, at: 3)
        pages = CaptionLayout.pages(in: p, style: .bold)
        #expect(pages.map(\.text) == ["one", "two three", "four five"])
        p.mergeCaptionWithPrevious(pages[2].words.map(\.wordID), in: pages[2].assetID, text: pages[2].text, previousFirst: pages[1].words[0].wordID)
        #expect(CaptionLayout.pages(in: p, style: .bold).map(\.text) == ["one", "two three four five"])
        // Subtitles would fit all five words on one page, but the user's captions stay.
        #expect(CaptionLayout.pages(in: p, style: .classic).map(\.text) == ["one", "two three four five"])
    }

    @Test func lineBreaksAreKeptAndShown() {
        var p = project(five)
        let page = CaptionLayout.pages(in: p, style: .classic)[0]
        p.replaceWords(page.words.map(\.wordID), in: page.assetID, with: "one two\nthree four five")
        let edited = CaptionLayout.pages(in: p, style: .classic)[0]
        #expect(edited.text == "one two\nthree four five")
        #expect(edited.plainText == "one two three four five")
        #expect(edited.lineBreaks == [1])
        #expect(edited.words[0].range.start == .zero)  // same words, same timing
    }

    @Test func draggingTheEndMakesTheCaptionEndExactlyThere() {
        var p = project([("hi", 1, 0.5)])
        var page = CaptionLayout.pages(in: p)[0]
        #expect(page.range.end == seconds(2))  // lingers half a second
        p.moveCaptionEdge(page, .end, to: seconds(1.2))
        page = CaptionLayout.pages(in: p)[0]
        #expect(page.range.end == seconds(1.2))
        p.moveCaptionEdge(page, .start, to: seconds(0.5))
        #expect(CaptionLayout.pages(in: p)[0].range.start == seconds(0.5))
    }

    @Test func captionEdgesStopAtTheWordsNextToThem() {
        var p = project([("a", 1, 0.5), ("b", 3, 0.5)])
        let pages = CaptionLayout.pages(in: p, style: .oneWord)
        p.moveCaptionEdge(pages[0], .end, to: seconds(5))
        #expect(p.transcripts.values.first?.words[0].end == seconds(3))
        p.moveCaptionEdge(CaptionLayout.pages(in: p, style: .oneWord)[1], .start, to: seconds(0))
        #expect(p.transcripts.values.first?.words[1].start == seconds(3))
    }

    @Test func edgesFollowSpeed() {
        var p = project([("hi", 2, 1)])
        p.timeline.clips[0].speed = 2
        p.timeline.clips[0].duration = seconds(5)
        let page = CaptionLayout.pages(in: p)[0]
        #expect(page.range.start == seconds(1))
        p.moveCaptionEdge(page, .start, to: seconds(0.5))  // source 1 s
        #expect(p.transcripts.values.first?.words[0].start == seconds(1))
    }

    @Test func phraseShowsAtMostFourWords() {
        let words = (0..<9).map { ("w\($0)", Double($0) * 0.3, 0.25) }
        let p = project(words)
        let pages = CaptionLayout.pages(in: p, style: .phrase)
        #expect(pages.allSatisfy { $0.words.count <= 4 })
        #expect(pages.count == 3)
    }

    @Test func newFieldsSurviveSaving() throws {
        var p = project(five)
        let page = CaptionLayout.pages(in: p, style: .bold)[0]
        p.splitCaption(page.words.map(\.wordID), in: page.assetID, text: "one\ntwo three", at: 3)
        p.setTranslations([page.words[0].wordID: CaptionTranslation(source: "one", text: "uno")])
        p.captions.translationLanguage = "it"
        p.transcripts[page.assetID]?.isTyped = true
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(Project.self, from: data)
        #expect(back.transcripts == p.transcripts)
        #expect(back.captions == p.captions)
    }
}

struct CaptionTranslationTests {
    @Test func aTranslationShowsOnlyWhileTheCaptionIsUnchanged() {
        var p = project([("ciao", 0, 0.5), ("mondo", 0.6, 0.5)])
        var page = CaptionLayout.pages(in: p)[0]
        p.setTranslations([page.words[0].wordID: CaptionTranslation(source: page.plainText, text: "hello world")])
        page = CaptionLayout.pages(in: p)[0]
        #expect(page.translation == "hello world")
        #expect(p.captionsNeedingTranslation().isEmpty)
        p.replaceWords(page.words.map(\.wordID), in: page.assetID, with: "ciao gente")
        #expect(CaptionLayout.pages(in: p)[0].translation == nil)
        #expect(p.captionsNeedingTranslation().count == 1)
    }
}

struct SRTTests {
    @Test func readsAnSRTFile() throws {
        let file = "\u{FEFF}1\r\n00:00:01,000 --> 00:00:02,500\r\nHello <i>there</i>\r\nfriend\r\n\r\n2\r\n00:00:03.2 --> 00:00:04,000 X1:0\r\nBye\r\n"
        let cues = try SRT.cues(from: file)
        #expect(cues.count == 2)
        #expect(cues[0] == CaptionCue(start: seconds(1), end: seconds(2.5), text: "Hello there\nfriend"))
        #expect(cues[1].start == seconds(3.2))
        #expect(cues[1].text == "Bye")
    }

    @Test func aFileWithoutSubtitlesIsRejected() {
        #expect(throws: SRT.ReadError.noSubtitles) { try SRT.cues(from: "just some text") }
    }

    @Test func writesTheCaptionsAsAnSRTFile() {
        var p = project([("one", 0, 0.4), ("two.", 0.5, 0.4), ("three", 1.5, 0.4)])
        let first = CaptionLayout.pages(in: p)[0]
        p.replaceWords(first.words.map(\.wordID), in: first.assetID, with: "one\ntwo.")
        let text = SRT.text(for: CaptionLayout.pages(in: p))
        #expect(text == "1\n00:00:00,000 --> 00:00:01,400\none\ntwo.\n\n2\n00:00:01,500 --> 00:00:02,400\nthree\n")
    }

    @Test func importingPlacesEachCueAsOneCaption() throws {
        var p = project([("old", 1, 0.5)])
        let cues = [CaptionCue(start: seconds(1), end: seconds(2), text: "Hello big\nworld"), CaptionCue(start: seconds(2), end: seconds(3.5), text: "again")]
        #expect(p.importCaptions(cues, language: .italian) == 2)
        let pages = CaptionLayout.pages(in: p, style: .bold)
        #expect(pages.map(\.text) == ["Hello big\nworld", "again"])
        #expect(pages[0].range == CMTimeRange(start: seconds(1), end: seconds(2)))
        #expect(pages[1].range.end == seconds(3.5))
        #expect(p.transcripts.values.allSatisfy { $0.isTyped })
        #expect(p.assetsNeedingTranscription(in: .english).isEmpty)
    }

    @Test func importedCaptionsGoToTheVoiceOverAndFollowIt() throws {
        var p = project([])
        p.timeline.clips[0].isMuted = true
        let voice = asset("voice", length: 5, video: false)
        p.addAsset(voice)
        let made = p.addSound(of: voice.id, at: seconds(2), isVoiceOver: true)
        let id = try #require(made)
        p.importCaptions([CaptionCue(start: seconds(3), end: seconds(4), text: "spoken")], language: .english)
        #expect(p.transcripts[voice.id]?.words.first?.start == seconds(1))
        p.updateSound(id) { $0.start = seconds(4) }
        #expect(CaptionLayout.pages(in: p)[0].range.start == seconds(5))
    }

    @Test func cuesThatTouchAtOddTimesAreAllKept() throws {
        var p = project([])
        let voice = asset("voice", length: 5, video: false)
        p.addAsset(voice)
        _ = p.addSound(of: voice.id, at: seconds(1.8), isVoiceOver: true)
        let cues = [CaptionCue(start: seconds(4.62), end: seconds(5.58), text: "semplice per studiare"),
                    CaptionCue(start: seconds(5.58), end: seconds(6), text: "meglio")]
        #expect(p.importCaptions(cues, language: .italian) == 2)
        #expect(CaptionLayout.pages(in: p).map(\.text) == ["semplice per studiare", "meglio"])
    }

    @Test func roundTrip() throws {
        var p = project([])
        let cues = [CaptionCue(start: seconds(0.5), end: seconds(1.5), text: "A first line"), CaptionCue(start: seconds(2), end: seconds(3), text: "Second")]
        p.importCaptions(cues, language: .english)
        let again = try SRT.cues(from: SRT.text(for: CaptionLayout.pages(in: p)))
        #expect(again == cues)
    }
}

struct SmartWordsTests {
    private func timed(_ texts: [String]) -> [TimedWord] {
        texts.map { TimedWord(wordID: UUID(), assetID: UUID(), clipID: UUID(), text: $0, range: CMTimeRange(start: .zero, duration: seconds(0.3))) }
    }

    @Test func numbersTheWordsForTheModel() {
        #expect(SmartWords.numbered(timed(["Ciao", "tipo", "mondo"])) == "[1] Ciao [2] tipo [3] mondo")
        #expect(SmartWords.chunks(of: timed(Array(repeating: "a", count: 250)), size: 120).map(\.count) == [120, 120, 10])
    }

    @Test func badAnswersAreDropped() {
        let words = timed(["So", "like", "1000", "euros", "amazing"])
        let picks = SmartWords.picks(in: words, keywords: [3, 5, 9], fillers: [2, 3, 0], emoji: [(4, "💰"), (5, "wow"), (1, "🔥🔥"), (2, "❤️")])
        #expect(picks.keywords == [words[2].wordID, words[4].wordID])
        #expect(picks.fillers == [words[1].wordID])
        #expect(picks.emoji == [words[3].wordID: "💰", words[1].wordID: "❤️"])
    }

    @Test func modelFillersAreCutLikeFillerSounds() {
        var p = project([("tipo", 0, 0.3), ("andiamo", 0.5, 0.4), ("eh", 1, 0.3), ("ora", 1.5, 0.3)])
        let tipo = p.script[0].wordID
        #expect(p.fillerAndRepeatedWords().map(\.wordID) == [p.script[2].wordID])
        #expect(Set(p.fillerAndRepeatedWords(also: [tipo]).map(\.wordID)) == [tipo, p.script[2].wordID])
        _ = p.setKeywords([p.script[1].wordID])
        #expect(p.script[1].isKeyword && !p.script[0].isKeyword)
    }

    @Test func atMostOneModelEmojiPerCaption() {
        var p = project([("money", 0, 0.3), ("love", 0.4, 0.3)])
        let ids = p.script.map(\.wordID)
        #expect(p.setEmoji([ids[0]: "💰", ids[1]: "❤️"]) == 1)
    }
}

struct LanguageGuessTests {
    @Test func moreSureWordsWin() {
        let right = LanguageGuess.score(confidences: Array(repeating: 0.9, count: 30))
        let wrong = LanguageGuess.score(confidences: Array(repeating: 0.4, count: 22))
        let lucky = LanguageGuess.score(confidences: [1, 1])
        #expect(right > wrong)
        #expect(right > lucky)
        #expect(LanguageGuess.score(confidences: []) == 0)
    }
}
