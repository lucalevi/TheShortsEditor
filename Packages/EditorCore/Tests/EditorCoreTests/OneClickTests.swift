import CoreGraphics
import CoreMedia
import Foundation
import Testing
@testable import EditorCore

private func t(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600).snappedToFrame() }

private func video(_ name: String, seconds: Int64 = 10) -> MediaAsset {
    MediaAsset(url: URL(fileURLWithPath: "/tmp/\(name)"), name: name, duration: CMTime(value: seconds, timescale: 1),
               displaySize: CGSize(width: 1080, height: 1920), hasAudio: true)
}

private func song(_ name: String) -> MediaAsset {
    MediaAsset(url: URL(fileURLWithPath: "/tmp/\(name)"), name: name, duration: CMTime(value: 184, timescale: 1),
               displaySize: .zero, hasAudio: true, hasVideo: false)
}

/// Words one a second, starting at `from` seconds, each half a second long.
private func words(_ texts: [String], from: Double = 0) -> Transcript {
    Transcript(language: .english, words: texts.enumerated().map { index, text in
        Word(text: text, start: t(from + Double(index)), duration: t(0.5))
    })
}

/// Sound levels per frame (30 a second): loud where `loud` says, quiet elsewhere.
private func levels(seconds: Int, loud: (Double) -> Bool) -> AudioLevels {
    AudioLevels(decibels: (0..<(seconds * 30)).map { loud(Double($0) / 30) ? -12 : -70 })
}

struct ShortStyleTests {
    @Test func aStyleRestylesTitlesCaptionsAndCuts() {
        var p = Project()
        let a = p.addAsset(video("a.mov")), b = p.addAsset(video("b.mov"))
        p.appendClip(of: a)
        p.appendClip(of: b)
        p.appendClip(of: b)
        let title = p.addTitle(at: .zero, text: "Hook")
        p.applyStyle(.pop)
        #expect(p.style == .pop)
        #expect(p.title(id: title)?.look == ShortStyle.pop.titleLook)
        #expect(p.title(id: title)?.entrance == .zoom)
        #expect(p.captions.style == .highlight)
        #expect(p.captions.accentColor == ShortStyle.pop.captionAccent)
        // A transition where the recording changes; the cut inside one recording stays plain.
        #expect(p.timeline.clips[0].transitionOut?.kind == .zoom)
        #expect(p.timeline.clips[1].transitionOut == nil)
        #expect(p.look == ShortStyle.pop.filter)
        // Pop punches in on the second clip of the same recording.
        #expect(p.timeline.clips[2].placement.scale == Placement.punchInScale)
        #expect(p.timeline.clips[2].styledMotion)
    }

    @Test func switchingStylesReplacesWhatTheOldOneDid() {
        var p = Project()
        let a = p.addAsset(video("a.mov"))
        p.appendClip(of: a)
        p.appendClip(of: a)
        p.applyStyle(.cinematic)
        #expect(p.timeline.clips.allSatisfy { $0.hasMotion && $0.styledMotion })
        #expect(p.look?.filter == .film)
        p.applyStyle(.clean)
        #expect(p.timeline.clips.allSatisfy { !$0.hasMotion && $0.placement == .identity && !$0.styledMotion })
        #expect(p.look == nil)
    }

    @Test func handMadeChoicesAreKept() {
        var p = Project()
        let a = p.addAsset(video("a.mov"))
        p.appendClip(of: a)
        p.appendClip(of: a)
        p.timeline.clips[0].placement.offsetX = 0.2          // moved by hand
        p.look = FilterChoice(.noir)                        // a filter the user chose
        let own = p.addAsset(song("mine.m4a"))
        p.setMusic(own)
        p.applyStyle(.cinematic, music: song("Dramatic.m4a"))
        #expect(p.timeline.clips[0].placement.offsetX == 0.2)
        #expect(!p.timeline.clips[0].hasMotion && !p.timeline.clips[0].styledMotion)
        #expect(p.timeline.clips[1].styledMotion)
        #expect(p.look?.filter == .noir)
        #expect(p.music?.assetID == own)
        #expect(p.music?.isMoodMusic == false)
    }

    @Test func styleMusicIsReplacedAndRemovedWithTheStyle() {
        var p = Project()
        p.appendClip(of: p.addAsset(video("a.mov")))
        p.applyStyle(.bold, music: song("Upbeat.m4a"))
        #expect(p.music?.mood == .upbeat)
        #expect(p.music?.volume == MusicMood.upbeat.volume)
        p.applyStyle(.vlog, music: song("Chill.m4a"))
        #expect(p.music?.mood == .chill)
        #expect(p.asset(id: p.music!.assetID)?.name == "Chill.m4a")
        p.applyStyle(nil)
        #expect(p.music == nil)
        #expect(p.style == nil)
    }

    @Test func noStyleTakesAwayOnlyItsOwnTransitions() {
        var p = Project()
        let a = p.addAsset(video("a.mov")), b = p.addAsset(video("b.mov")), c = p.addAsset(video("c.mov"))
        p.appendClip(of: a)
        p.appendClip(of: b)
        p.appendClip(of: c)
        p.applyStyle(.explainer)
        p.setTransition(ClipTransition(kind: .whip), after: p.timeline.clips[1].id)
        p.applyStyle(nil)
        #expect(p.timeline.clips[0].transitionOut == nil)
        #expect(p.timeline.clips[1].transitionOut?.kind == .whip)
    }

    @Test func newTitlesMatchTheStyle() {
        var p = Project()
        p.appendClip(of: p.addAsset(video("a.mov")))
        p.applyStyle(.explainer)
        let id = p.addTitle(at: .zero, text: "Hello")
        #expect(p.title(id: id)?.look == ShortStyle.explainer.titleLook)
        #expect(p.title(id: id)?.entrance == .slideUp)
    }

    @Test func moodMusicEndsOnTheBeat() {
        var p = Project()
        p.appendClip(of: p.addAsset(video("a.mov", seconds: 10)))
        p.applyStyle(.bold, music: song("Upbeat.m4a"))
        let music = try! #require(p.music)
        let bar = MusicMood.upbeat.barLength.seconds
        let end = music.sourceStart.seconds + p.duration.seconds
        let bars = end / bar
        #expect(abs(bars - bars.rounded()) < 0.001)
        #expect(!music.fadesOut && !music.fadesIn)
        // Shorter Short: the start moves so it still ends on the beat.
        p.trimClip(p.timeline.clips[0].id, edge: .end, by: t(-1.3))
        p.fitMoodMusic()
        let after = (p.music!.sourceStart.seconds + p.duration.seconds) / bar
        #expect(abs(after - after.rounded()) < 0.001)
    }

    @Test func stylesAreSaved() throws {
        var p = Project()
        p.appendClip(of: p.addAsset(video("a.mov")))
        p.appendClip(of: p.addAsset(video("b.mov")))
        p.applyStyle(.vlog, music: song("Chill.m4a"))
        let data = try ProjectFile(project: p).encoded()
        let back = try ProjectFile.decode(data).project
        #expect(back == p)
        #expect(back.music?.mood == .chill)
        #expect(back.timeline.clips[0].styledMotion)
    }
}

struct MagicShortTests {
    @Test func hookTitleComesFromTheFirstSentence() {
        func timed(_ texts: [String]) -> [TimedWord] {
            texts.map { TimedWord(wordID: UUID(), assetID: UUID(), clipID: UUID(), text: $0, range: CMTimeRange(start: .zero, duration: t(0.5))) }
        }
        #expect(MagicShort.hookText(from: timed(["this", "is", "my", "trick.", "And", "more"])) == "This is my trick")
        #expect(MagicShort.hookText(from: timed(["did", "you", "know?", "Yes"])) == "Did you know?")
        #expect(MagicShort.hookText(from: timed(["one", "two", "three", "four", "five", "six", "seven", "eight."])) == "One two three four five…")
        #expect(MagicShort.hookText(from: []) == nil)
    }

    @Test func magicCutsFillersAndPausesAddsHookAndEndsTight() {
        var p = Project()
        let a = p.addAsset(video("talk.mov", seconds: 12))
        p.appendClip(of: a)
        // Words at 0…5 s, a filler at 2 s, then nothing (a long silent tail).
        p.transcripts[a] = words(["Here's", "a", "um", "great", "tip."])
        let sound = levels(seconds: 12) { $0 < 5 && $0.truncatingRemainder(dividingBy: 1) < 0.5 }
        var options = MagicOptions(style: .bold)
        options.addsMusic = true
        let report = p.makeMagic(options, levels: [a: sound], music: song("Upbeat.m4a"))
        #expect(report.removedFillers == 1)
        #expect(report.hasSpeech)
        #expect(!p.script.contains { $0.text == "um" })
        // The pauses and the silent tail are gone: four words of half a second, a little padding.
        #expect(p.duration < t(4))
        #expect(p.duration > t(2))
        let hook = try! #require(report.hookTitleID.flatMap(p.title(id:)))
        #expect(hook.text == "Here's a great tip")
        #expect(hook.start == .zero)
        #expect(hook.look == ShortStyle.bold.titleLook)
        #expect(p.captions.isVisible)
        #expect(p.style == .bold)
        #expect(p.music?.mood == .upbeat)
        // Bold punches in on every other piece of the talk.
        #expect(p.timeline.clips.contains { $0.placement.scale == Placement.punchInScale })
        // The last word is followed by only the end padding.
        let lastWord = try! #require(p.script.last)
        #expect(p.duration - lastWord.range.end <= MagicShort.endPadding + .oneFrame)
    }

    @Test func quietFootageBecomesAMontage() {
        var p = Project()
        let a = p.addAsset(video("beach.mov", seconds: 20)), b = p.addAsset(video("city.mov", seconds: 3))
        p.appendClip(of: a)
        p.appendClip(of: b)
        let report = p.makeMagic(MagicOptions(style: .vlog), levels: [:], music: nil)
        #expect(!report.hasSpeech)
        #expect(report.hookNeedsText)
        #expect(p.titles.first?.text == MagicShort.placeholderHook)
        // The long clip keeps its middle 4 seconds; the short one stays whole.
        #expect(p.timeline.clips[0].duration == MagicShort.quietClipLength)
        #expect(p.timeline.clips[0].sourceStart == t(8))
        #expect(p.timeline.clips[1].duration == t(3))
        #expect(!p.captions.isVisible)
    }

    @Test func fittingToALengthEndsOnASentence() {
        var p = Project()
        let a = p.addAsset(video("talk.mov", seconds: 60))
        p.appendClip(of: a)
        var texts: [String] = []
        for i in 0..<60 { texts.append(i % 5 == 4 ? "end." : "word") }
        p.transcripts[a] = words(texts)
        p.fit(to: t(30))
        // Sentences end at 4.5, 9.5 … 29.5 s: the last one fits with its padding.
        #expect(p.duration == (t(29.5) + MagicShort.endPadding).snappedToFrame())
        p.fit(to: t(29.6))
        #expect(p.duration == (t(24.5) + MagicShort.endPadding).snappedToFrame())
    }

    @Test func fittingQuietFootageSharesTheCut() {
        var p = Project()
        let a = p.addAsset(video("a.mov", seconds: 40)), b = p.addAsset(video("b.mov", seconds: 40))
        p.appendClip(of: a)
        p.appendClip(of: b)
        p.fit(to: t(30))
        #expect(p.duration <= t(30))
        #expect(p.duration >= t(29.9))
        #expect(p.timeline.clips[0].duration == p.timeline.clips[1].duration)
        #expect(p.timeline.clips[0].sourceStart == t(12.5))
    }

    @Test func turningPartsOffLeavesThemOut() {
        var p = Project()
        let a = p.addAsset(video("talk.mov", seconds: 6))
        p.appendClip(of: a)
        p.transcripts[a] = words(["Hello", "um", "there."])
        var options = MagicOptions(style: .clean)
        options.removesFillers = false
        options.removesPauses = false
        options.showsCaptions = false
        options.addsHookTitle = false
        options.addsMusic = false
        p.makeMagic(options, levels: [:], music: song("Calm.m4a"))
        #expect(p.script.contains { $0.text == "um" })
        #expect(p.titles.isEmpty)
        #expect(p.music == nil)
        #expect(!p.captions.isVisible)
    }
}

struct StoryboardTests {
    @Test func everyTemplateHasAHookFirstAndAPlannedLength() {
        for kind in StoryboardKind.allCases {
            let board = Storyboard(kind: kind)
            #expect(board.slots.first?.shot.name == "Hook", "\(kind)")
            #expect(board.plannedLength >= t(15) && board.plannedLength <= t(45), "\(kind)")
            #expect(board.slots.first.map { $0.shot.length <= t(2) } == true)
        }
    }

    @Test func shotsFillInOrderWhateverOrderTheyAreFilled() throws {
        var p = Project()
        p.startStoryboard(.topThree)
        let board = try #require(p.storyboard)
        let a = p.addAsset(video("a.mov")), b = p.addAsset(video("b.mov")), c = p.addAsset(video("c.mov"))
        let threeFilled = p.fill(board.slots[1].id, with: a)
        let three = try #require(threeFilled)
        let oneFilled = p.fill(board.slots[3].id, with: c)
        let one = try #require(oneFilled)
        let twoFilled = p.fill(board.slots[2].id, with: b)
        let two = try #require(twoFilled)
        #expect(p.timeline.clips.map(\.id) == [three, two, one])
        // Talking shots keep the whole clip.
        #expect(p.timeline.clips.allSatisfy { $0.duration == t(10) })
        // Each numbered shot got its title, over the start of its clip.
        let titles = p.titles.map(\.text)
        #expect(Set(titles) == ["#3", "#2", "#1"])
        let twoTitle = try #require(p.titles.first { $0.text == "#2" })
        #expect(twoTitle.start == p.timeline.range(of: two)?.start)
    }

    @Test func quickShotsAreTrimmedToTheirMiddle() throws {
        var p = Project()
        p.startStoryboard(.beforeAfter)
        let board = try #require(p.storyboard)
        let a = p.addAsset(video("room.mov", seconds: 10))
        let idFilled = p.fill(board.slots[1].id, with: a)
        let id = try #require(idFilled)   // "Before", 3 s
        let clip = try #require(p.timeline.clips.first { $0.id == id })
        #expect(clip.duration == t(3))
        #expect(clip.sourceStart == t(3.5))
    }

    @Test func refillingReplacesTheShotsClipAndTitle() throws {
        var p = Project()
        p.startStoryboard(.tutorial)
        let board = try #require(p.storyboard)
        let a = p.addAsset(video("a.mov")), b = p.addAsset(video("b.mov"))
        p.fill(board.slots[2].id, with: a)
        p.fill(board.slots[2].id, with: b)
        #expect(p.timeline.clips.count == 1)
        #expect(p.timeline.clips[0].assetID == b)
        #expect(p.titles.filter { $0.text == "Step 1" }.count == 1)
        p.empty(board.slots[2].id)
        #expect(p.timeline.clips.isEmpty)
        #expect(p.titles.isEmpty)
        #expect(p.storyboard?.slots[2].clipID == nil)
    }

    @Test func aDeletedClipLeavesItsShotEmpty() throws {
        var p = Project()
        p.startStoryboard(.story)
        let board = try #require(p.storyboard)
        let idFilled = p.fill(board.slots[0].id, with: p.addAsset(video("a.mov")))
        let id = try #require(idFilled)
        p.timeline.remove(id)
        #expect(p.clip(filling: p.storyboard!.slots[0]) == nil)
    }

    @Test func storyboardTitlesTakeTheStyle() throws {
        var p = Project()
        p.applyStyle(.bold)
        p.startStoryboard(.topThree)
        let board = try #require(p.storyboard)
        p.fill(board.slots[1].id, with: p.addAsset(video("a.mov")))
        #expect(p.titles.first?.look == ShortStyle.bold.titleLook)
    }

    @Test func storyboardsAreSaved() throws {
        var p = Project()
        p.startStoryboard(.review)
        let board = try #require(p.storyboard)
        p.fill(board.slots[0].id, with: p.addAsset(video("a.mov")))
        let back = try ProjectFile.decode(try ProjectFile(project: p).encoded()).project
        #expect(back.storyboard == p.storyboard)
        #expect(back.storyboard?.slots[0].shot.length == t(2))
    }
}

struct StyleBookkeepingTests {
    @Test func oldStyleMusicLeavesMedia() {
        var p = Project()
        p.appendClip(of: p.addAsset(video("a.mov")))
        p.applyStyle(.bold, music: song("Upbeat.m4a"))
        p.applyStyle(.vlog, music: song("Chill.m4a"))
        #expect(!p.assets.contains { $0.name == "Upbeat.m4a" })
        #expect(p.assets.contains { $0.name == "Chill.m4a" })
    }

    @Test func movingAStyledPictureByHandMakesItYours() {
        var p = Project()
        let a = p.addAsset(video("a.mov"))
        p.appendClip(of: a)
        p.appendClip(of: a)
        p.applyStyle(.bold)
        let old = p
        p.timeline.clips[1].placement.offsetX = 0.1
        p.claimHandMadeMotion(from: old)
        #expect(!p.timeline.clips[1].styledMotion)
        p.applyStyle(.clean)
        #expect(p.timeline.clips[1].placement.offsetX == 0.1)
    }
}
