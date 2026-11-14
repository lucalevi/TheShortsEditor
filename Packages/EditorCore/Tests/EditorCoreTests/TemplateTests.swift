import CoreGraphics
import CoreMedia
import Foundation
import Testing

@testable import EditorCore

private func t(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600).snappedToFrame() }

private func video(_ name: String, seconds: Double = 10) -> MediaAsset {
    MediaAsset(
        url: URL(fileURLWithPath: "/tmp/\(name)"), name: name, duration: CMTime(seconds: seconds, preferredTimescale: 600),
        displaySize: CGSize(width: 1080, height: 1920), hasAudio: true)
}

private func picture(_ name: String) -> MediaAsset {
    MediaAsset(
        url: URL(fileURLWithPath: "/tmp/\(name)"), name: name, duration: CMTime(value: 4, timescale: 1),
        displaySize: CGSize(width: 1080, height: 1920), hasAudio: false, isImage: true)
}

/// Sentences said one after another: each word half a second, a pause of `gap` between sentences.
private func spoken(_ sentences: [String], gap: Double = 0.6) -> Transcript {
    var words: [Word] = []
    var time = 0.0
    for sentence in sentences {
        for text in sentence.split(separator: " ") {
            words.append(Word(text: String(text), start: t(time), duration: t(0.4)))
            time += 0.5
        }
        time += gap
    }
    return Transcript(language: .english, words: words)
}

struct TemplateTests {
    // MARK: Templates

    @Test func everyCutFallsOnTheBeat() {
        for template in ShortTemplate.allCases {
            let beat = template.beatLength
            var cut = CMTime.zero
            var beats = 0
            for (shot, length) in zip(template.shots, template.shotLengths) {
                cut = cut + length
                beats += shot.beats
                // Within half a frame of its beat, however many shots before it.
                #expect(abs(cut.seconds - Double(beats) * beat) <= 0.5 / 30 + 0.0001, "\(template)")
                #expect(length == length.snappedToFrame())
            }
            // A whole number of bars, so app-made music ends on a bar line exactly there.
            #expect(beats % 4 == 0, "\(template)")
            #expect(template.shots.count >= 4)
            #expect(template.length.seconds > 10 && template.length.seconds < 60)
        }
    }

    @Test func fillingATemplateMakesTheShortToTheBeat() throws {
        var p = Project()
        let ids = [p.addAsset(video("a.mov")), p.addAsset(video("b.mov")), p.addAsset(picture("c.jpg"))]
        let template = ShortTemplate.countdown
        p.fillTemplate(template, with: ids)
        let board = try #require(p.storyboard)
        #expect(board.template == template)
        #expect(board.name == "Top 5")
        #expect(p.timeline.clips.count == template.shots.count)
        #expect(p.timeline.clips.map(\.duration) == template.shotLengths)
        #expect(p.duration == template.length)
        #expect(board.slots.allSatisfy { p.clip(filling: $0) != nil })
        // Each shot's text stays for the whole shot.
        let titled = template.shots.filter { $0.title != nil }.count
        #expect(p.titles.count == titled)
        let five = try #require(p.titles.first { $0.text == "#5" })
        #expect(five.start == template.shotLengths[0] && five.duration == template.shotLengths[1])
        // Transitions go on the clip before the shot that has one; the first comes in with its animation.
        for index in 0..<(template.shots.count - 1) {
            #expect(p.timeline.clips[index].transitionOut?.kind == template.shots[index + 1].transition)
        }
        #expect(p.timeline.clips.last?.transitionOut == nil)
        #expect(p.timeline.clips[0].animationIn?.kind == .pop)
        // a.mov used again later: a different part of it.
        let uses = p.timeline.clips.filter { $0.assetID == ids[0] }
        #expect(uses.count == 3)
        #expect(Set(uses.map(\.sourceStart)).count == 3)
    }

    @Test func aShortClipIsSlowedToFillItsShot() {
        var p = Project()
        let id = p.addAsset(video("short.mov", seconds: 1.5))
        p.fillTemplate(.beforeAfter, with: [id])
        let wanted = ShortTemplate.beforeAfter.shotLengths[0]
        let clip = p.timeline.clips[0]
        #expect(clip.duration == wanted)
        #expect(clip.speed < 0.6 && clip.speed >= Clip.speedRange.lowerBound)
        #expect(abs(clip.sourceDuration.seconds - 1.5) < 0.05)
    }

    @Test func aTemplateStoryboardIsSaved() throws {
        var p = Project()
        p.fillTemplate(.recipe, with: [p.addAsset(video("a.mov"))])
        let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(p))
        #expect(decoded.storyboard == p.storyboard)
        #expect(decoded.storyboard?.template == .recipe)
        #expect(decoded.storyboard?.slots[1].shot.fitsExactly == true)
        #expect(decoded.storyboard?.slots[1].shot.transition == .slideUp)
        // An ordinary storyboard still reads and has no template.
        p.startStoryboard(.tutorial)
        let plain = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(p))
        #expect(plain.storyboard?.template == nil)
        #expect(plain.storyboard?.slots.allSatisfy { !$0.shot.fitsExactly } == true)
    }

    @Test func swappingAShotKeepsTheBeat() {
        var p = Project()
        let a = p.addAsset(video("a.mov")), b = p.addAsset(video("b.mov", seconds: 30))
        p.fillTemplate(.montage, with: [a])
        let slot = p.storyboard!.slots[3]
        p.fill(slot.id, with: b)
        #expect(p.timeline.clips.map(\.duration) == ShortTemplate.montage.shotLengths)
        #expect(p.timeline.clips[3].assetID == b)
        #expect(p.timeline.clips[3].transitionOut?.kind == ShortTemplate.montage.shots[4].transition)
    }

    // MARK: Best moments

    @Test func sentencesAreSplitBySignsAndPauses() {
        var p = Project()
        let id = p.addAsset(video("talk.mov", seconds: 60))
        p.appendClip(of: id)
        p.transcripts[id] = spoken(["Hello everyone.", "Did you know this costs 5 euros?", "and then nothing"], gap: 1.5)
        let sentences = p.spokenSentences
        #expect(sentences.map(\.text) == ["Hello everyone.", "Did you know this costs 5 euros?", "and then nothing"])
        #expect(sentences[1].wordCount == 7)
        #expect(sentences[0].range.start == .zero)
    }

    @Test func theRulesPickALivelyRunThatFits() {
        var p = Project()
        let id = p.addAsset(video("talk.mov", seconds: 120))
        p.appendClip(of: id)
        p.transcripts[id] = spoken([
            "so yeah um I was thinking about stuff and things today.",
            "ok so anyway let me tell you about it now.",
            "Did you know that 9 out of 10 developers forget this?",
            "Unbelievable performance improvements happen immediately afterwards!",
            "It took 3 minutes to fix everything.",
            "anyway that is it for today see you.",
        ])
        let sentences = p.spokenSentences
        let run = MomentPicker.bestRun(sentences, target: 15)
        #expect(run.first == 2)
        let length = (sentences[run.last!].range.end - sentences[run.first!].range.start).seconds
        #expect(length <= 15)
        #expect(run.contains(4))
    }

    @Test func picksAreTidied() {
        var p = Project()
        let id = p.addAsset(video("talk.mov", seconds: 120))
        p.appendClip(of: id)
        p.transcripts[id] = spoken((1...10).map { "Sentence number \($0) has six words." })
        let sentences = p.spokenSentences
        // Out of order, repeated, out of range: sorted and cleaned, then cut to fit 9 s (3 s each).
        let tidied = MomentPicker.tidy([7, 2, 2, 99, 4, 5], in: sentences, target: 9)
        #expect(tidied?.first == 2)
        #expect(tidied?.count == 3)
        #expect(tidied == tidied?.sorted())
        // Almost nothing usable: the rules take over.
        #expect(MomentPicker.tidy([99], in: sentences, target: 9) == nil)
        #expect(MomentPicker.tidy([], in: sentences, target: 9) == nil)
    }

    @Test func onlyTheChosenSentencesAreKept() {
        var p = Project()
        let id = p.addAsset(video("talk.mov", seconds: 60))
        p.appendClip(of: id)
        p.transcripts[id] = spoken(["One two three.", "Four five six.", "Seven eight nine.", "Ten eleven twelve."], gap: 1)
        let sentences = p.spokenSentences
        p.keepSentences(startingWith: [sentences[1].firstWordID, sentences[3].firstWordID])
        #expect(p.spokenSentences.map(\.text) == ["Four five six.", "Ten eleven twelve."])
        #expect(p.duration < CMTime(value: 60, timescale: 1))
    }

    @Test func magicShortKeepsTheChosenMoments() throws {
        var p = Project()
        let id = p.addAsset(video("talk.mov", seconds: 60))
        p.appendClip(of: id)
        p.transcripts[id] = spoken((1...16).map { "This is sentence \($0) right here." }, gap: 0.3)
        var options = MagicOptions(style: .clean, length: .about30)
        options.addsMusic = false
        options.addsHookTitle = false
        options.removesPauses = false
        // About 53 s of talk for 30 s: there is something to choose.
        let sentences = p.magicSentences(options, levels: [:])
        #expect(sentences.count == 16)
        let picks = try #require(MomentPicker.tidy([3, 4, 8, 9, 10, 15], in: sentences, target: 30))
        options.keptSentences = Set(picks.map { sentences[$0].firstWordID })
        let report = p.makeMagic(options, levels: [:], music: nil)
        #expect(p.spokenSentences.map(\.text) == picks.map { sentences[$0].text })
        #expect(report.keptSentences == picks.count && report.sentencesSaid == 16)
        #expect(p.duration <= CMTime(value: 30, timescale: 1))
        // "Keep it all" has nothing to choose.
        #expect(p.magicSentences(MagicOptions(style: .clean, length: .keepAll), levels: [:]).isEmpty)
    }
}

struct CoverTests {
    @Test func theSuggestedCoverTakesTheHook() {
        var p = Project()
        p.appendClip(of: p.addAsset(video("a.mov")))
        _ = p.addTitle(at: .zero, text: "Watch this")
        let cover = p.suggestedCover
        #expect(cover.time == CMTime(value: 1, timescale: 1))
        #expect(cover.text == "Watch this")
        #expect(!cover.showsCaptions)
    }

    @Test func theCoverIsDrawnWithItsOwnBigText() {
        var p = Project()
        p.appendClip(of: p.addAsset(video("a.mov")))
        p.applyStyle(.pop)
        _ = p.addTitle(at: .zero, text: "Old title")
        _ = p.addTitle(at: CMTime(value: 8, timescale: 1), text: "Later title")
        p.captions.isVisible = true
        let cover = ShortCover(time: CMTime(value: 1, timescale: 1), text: "  My cover  ", textPosition: 0.3)
        let drawn = p.coverProject(cover)
        #expect(!drawn.captions.isVisible)
        // The title on screen then gives way; one later stays.
        #expect(drawn.titles.map(\.text) == ["Later title", "My cover"])
        let title = drawn.titles.last!
        #expect(title.look.size == ShortCover.textSize)
        #expect(title.entrance == .none)
        #expect(title.verticalPosition == 0.3)
        #expect(title.start == cover.time)
        // Without text, nothing is added; with captions asked for, they stay.
        var plain = cover
        plain.text = ""
        plain.showsCaptions = true
        #expect(p.coverProject(plain).titles.count == 2)
        #expect(p.coverProject(plain).captions.isVisible)
    }

    @Test func theCoverIsSavedAndIsThePoster() throws {
        var p = Project()
        p.appendClip(of: p.addAsset(video("a.mov")))
        #expect(p.posterTime == nil)
        p.cover = ShortCover(time: CMTime(value: 30, timescale: 1), text: "Hi")
        // Past the end (the Short got shorter): its last frame.
        #expect(p.posterTime == p.duration - .oneFrame)
        let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(p))
        #expect(decoded.cover == p.cover)
    }
}
