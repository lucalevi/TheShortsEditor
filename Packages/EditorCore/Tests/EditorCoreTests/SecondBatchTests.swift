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
    MediaAsset(url: URL(fileURLWithPath: "/tmp/\(name)"), name: name, duration: CMTime(seconds: seconds, preferredTimescale: 600), displaySize: .zero, hasAudio: true, hasVideo: false)
}

/// One 10 s video with a transcript: a word every second ("w0" … "w9"), each half a second long.
private func talking(words: [String]? = nil) -> (Project, MediaAsset.ID) {
    var p = Project()
    let id = p.addAsset(video())
    p.appendClip(of: id)
    let texts = words ?? (0..<10).map { "w\($0)" }
    p.transcripts[id] = Transcript(language: .english, words: texts.enumerated().map { index, text in
        Word(text: text, start: seconds(Double(index)), duration: seconds(0.5))
    })
    return (p, id)
}

// MARK: - Speed

struct SpeedTests {
    @Test func fasterIsShorterAndShowsTheSamePart() {
        var (p, _) = talking()
        let id = p.timeline.clips[0].id
        p.setSpeed(2, for: id)
        #expect(p.duration == seconds(5))
        #expect(p.timeline.clips[0].sourceRange == CMTimeRange(start: .zero, duration: seconds(10)))
        #expect(p.timeline.clips[0].sourceTime(atOffset: seconds(1)) == seconds(2))
    }

    @Test func speedIsKeptInRange() {
        var (p, _) = talking()
        p.setSpeed(20, for: p.timeline.clips[0].id)
        #expect(p.timeline.clips[0].speed == Clip.speedRange.upperBound)
    }

    @Test func captionsFollowTheSpeed() {
        var (p, _) = talking()
        p.setSpeed(2, for: p.timeline.clips[0].id)
        let words = CaptionLayout.timelineWords(in: p)
        let w4 = words.first { $0.text == "w4" }
        #expect(w4?.range.start == seconds(2))
        #expect(abs((w4?.range.duration.seconds ?? 0) - 0.25) < 0.02)
    }

    @Test func splittingAFastClipCutsTheRightPlace() {
        var (p, _) = talking()
        p.setSpeed(2, for: p.timeline.clips[0].id)
        p.timeline.split(at: seconds(1))
        #expect(p.timeline.clips[1].sourceStart == seconds(2))
        #expect(p.timeline.clips[1].speed == 2)
        #expect(p.duration == seconds(5))
    }

    @Test func trimmingAFastClipMovesTheSourceTwiceAsFar() {
        var (p, _) = talking()
        let id = p.timeline.clips[0].id
        p.setSpeed(2, for: id)
        p.trimClip(id, edge: .start, by: seconds(1))
        #expect(p.timeline.clips[0].sourceStart == seconds(2))
        #expect(p.duration == seconds(4))
        // The end can't go past the file: at most 4 s more of timeline… which is all there is.
        p.trimClip(id, edge: .end, by: seconds(10))
        #expect(p.duration == seconds(4))
    }

    @Test func slowMotionMakesItLonger() {
        var (p, _) = talking()
        p.setSpeed(0.5, for: p.timeline.clips[0].id)
        #expect(p.duration == seconds(20))
    }

    @Test func picturesHaveNoSpeed() {
        var p = Project()
        p.appendClip(of: p.addAsset(.image(url: URL(fileURLWithPath: "/tmp/a.png"), size: CGSize(width: 10, height: 10))))
        p.setSpeed(2, for: p.timeline.clips[0].id)
        #expect(p.timeline.clips[0].speed == 1)
    }

    @Test func pausesAreFoundAtTheRightPlaceOnAFastClip() {
        var (p, id) = talking()
        p.setSpeed(2, for: p.timeline.clips[0].id)
        // Loud for the first 2 s of the file, then quiet.
        let levels = AudioLevels(decibels: (0..<300).map { $0 < 60 ? -10 : -80 })
        let plan = SilencePlan.make(for: p, levels: [id: levels], settings: SilenceSettings(threshold: -40, padding: .zero))
        #expect(plan.timelineCuts.first?.start == seconds(1))
        p.apply(plan)
        #expect(p.duration == seconds(1))
    }
}

// MARK: - Title looks

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

// MARK: - Key words and emoji

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

// MARK: - Edit by text

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

// MARK: - Sound effects and voice-overs

struct SoundTests {
    @Test func aSoundIsAddedWholeAtThePlayhead() throws {
        var (p, _) = talking()
        let added = p.addSound(of: p.addAsset(sound()), at: seconds(2))
        let addedID = try #require(added)
        let sound = try #require(p.sound(id: addedID))
        #expect(sound.start == seconds(2) && sound.duration == seconds(1))
        #expect(p.allTimelineItems.contains(.sound(sound.id)))
    }

    @Test func aLongSoundStopsWithTheShort() throws {
        var (p, _) = talking()
        let added = p.addSound(of: p.addAsset(sound("voice.m4a", seconds: 30)), at: seconds(4))
        let addedID = try #require(added)
        #expect(p.sound(id: addedID)?.end == seconds(10))
    }

    @Test func picturesAreNotSounds() {
        var (p, _) = talking()
        let id = p.addSound(of: p.addAsset(.image(url: URL(fileURLWithPath: "/tmp/a.png"), size: CGSize(width: 1, height: 1))), at: .zero)
        #expect(id == nil)
    }

    @Test func soundsMoveTrimSplitAndDelete() throws {
        var (p, _) = talking()
        let added = p.addSound(of: p.addAsset(sound("whoosh.m4a", seconds: 3)), at: seconds(1))
        let id = try #require(added)
        p.moveSound(id, to: seconds(2))
        #expect(p.sound(id: id)?.start == seconds(2))
        p.trimSound(id, edge: .start, by: seconds(1))
        #expect(p.sound(id: id)?.start == seconds(3))
        #expect(p.sound(id: id)?.clip.sourceStart == seconds(1))
        let split = p.splitSound(id, at: seconds(4))
        #expect(split != nil)
        #expect(p.sounds.count == 2)
        p.remove([.sound(id)])
        #expect(p.sounds.count == 1)
    }

    @Test func theMusicIsLoweredUnderAVoiceOver() throws {
        var (p, _) = talking()
        p.addSound(of: p.addAsset(sound("voice.m4a", seconds: 2)), at: seconds(5), isVoiceOver: true)
        p.addSound(of: p.addAsset(sound("pop.m4a", seconds: 1)), at: seconds(1))
        let speech = AudioMix.speechRanges(in: p, levels: [:])
        #expect(speech == [CMTimeRange(start: seconds(5), duration: seconds(2))])
    }

    @Test func soundsAreSaved() throws {
        var (p, _) = talking()
        let effect = p.addAsset(sound())
        p.addSound(of: effect, at: seconds(1))
        let read = try ProjectFile.decode(ProjectFile(project: p).encoded()).project
        #expect(read.sounds == p.sounds)
        #expect(read.usedAssets.contains { $0.id == effect })
    }
}

// MARK: - Layouts and reframing

struct LayoutTests {
    @Test func aSplitLayoutSharesTheScreen() throws {
        var (p, _) = talking()
        let added = p.addOverlay(of: p.addAsset(video("broll.mov")), at: seconds(1))
        let id = try #require(added)
        p.updateOverlay(id) { $0.layout = .top }
        let regions = p.regions(at: seconds(2))
        #expect(regions.overlays[id] == CGRect(x: 0, y: 0, width: 1080, height: 960))
        #expect(regions.main == CGRect(x: 0, y: 960, width: 1080, height: 960))
        // Before the B-roll starts, the main clip has the whole screen.
        #expect(p.regions(at: seconds(0.5)).main.height == 1920)
    }

    @Test func pictureInPictureCornersStayClearOfYouTubesButtons() {
        for corner in PictureCorner.allCases {
            for size in [CGSize(width: 1080, height: 1920), CGSize(width: 1920, height: 1080)] {
                let placement = Placement.pictureInPicture(corner, displaySize: size, framing: .fill)
                let frame = Framing.fill.placedFrame(of: size, placement: placement)
                let rect = CGRect(x: frame.center.x - frame.size.width / 2, y: frame.center.y - frame.size.height / 2,
                                  width: frame.size.width, height: frame.size.height)
                #expect(!SafeZone.covers(rect), "\(corner) \(size)")
                #expect(CGRect(origin: .zero, size: Project.canvasSize).contains(rect))
            }
        }
    }

    @Test func aPictureInARegionIsPlacedInsideIt() {
        let region = CGRect(x: 0, y: 960, width: 1080, height: 960)
        let frame = Framing.fill.placedFrame(of: CGSize(width: 1920, height: 1080), placement: .identity, region: region)
        #expect(frame.center == CGPoint(x: 540, y: 1440))
        #expect(frame.covers(region))
    }

    @Test func reframingFollowsTheSubjectAcross() {
        let clip = Clip(assetID: UUID(), sourceStart: .zero, duration: seconds(4))
        let horizontal = CGSize(width: 1920, height: 1080)
        // The subject walks from the left third to the right third.
        let samples = stride(from: 0.0, through: 4, by: 0.25).map { Reframe.Sample(time: seconds($0), x: 0.3 + 0.4 * $0 / 4) }
        let frames = Reframe.keyframes(for: clip, displaySize: horizontal, samples: samples)
        #expect(frames.count >= 2)
        #expect(frames.first!.placement.offsetX > 0)   // subject on the left: picture moves right
        #expect(frames.last!.placement.offsetX < 0)
        let room = (Framing.fill.framedSize(of: horizontal).width - 1080) / 2 / 1080
        #expect(frames.allSatisfy { abs($0.placement.offsetX) <= room + 0.0001 })
    }

    @Test func aStillSubjectGivesOneKeyframe() {
        let clip = Clip(assetID: UUID(), sourceStart: .zero, duration: seconds(4))
        let samples = stride(from: 0.0, through: 4, by: 0.5).map { Reframe.Sample(time: seconds($0), x: 0.4) }
        #expect(Reframe.keyframes(for: clip, displaySize: CGSize(width: 1920, height: 1080), samples: samples).count == 1)
    }

    @Test func verticalFootageHasNothingToFollow() {
        let clip = Clip(assetID: UUID(), sourceStart: .zero, duration: seconds(4))
        #expect(Reframe.keyframes(for: clip, displaySize: CGSize(width: 1080, height: 1920), samples: [Reframe.Sample(time: .zero, x: 0.1)]).isEmpty)
    }
}
