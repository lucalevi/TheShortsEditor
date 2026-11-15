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
