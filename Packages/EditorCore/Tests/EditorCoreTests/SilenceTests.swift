import CoreMedia
import Foundation
import Testing
@testable import EditorCore

private func frames(_ n: Int64) -> CMTime { CMTime(value: n, timescale: 30) }

/// Levels from a pattern: "#" is a loud frame (-10 dB), "." a quiet one (-80 dB).
private func levels(_ pattern: String) -> AudioLevels {
    AudioLevels(decibels: pattern.map { $0 == "#" ? -10 : -80 })
}

private func project(_ pattern: String, hasAudio: Bool = true) -> Project {
    var project = Project()
    let asset = MediaAsset(url: URL(fileURLWithPath: "/tmp/a.mov"), name: "a", duration: frames(Int64(pattern.count)),
                           displaySize: CGSize(width: 1080, height: 1920), hasAudio: hasAudio)
    project.addAsset(asset)
    project.appendClip(of: asset.id)
    return project
}

private let settings = SilenceSettings(threshold: -40, padding: frames(2), minimumPause: frames(5))

struct SilenceTests {
    @Test func cutsLongPausesAndKeepsPaddingAroundSpeech() {
        //                 0         1         2
        //                 0123456789012345678901234
        let pattern =     "#####..........##########"
        let p = project(pattern)
        let plan = SilencePlan.make(for: p, levels: [p.assets[0].id: levels(pattern)], settings: settings)
        // Quiet frames 5..<15, minus 2 frames of padding each side.
        #expect(plan.timelineCuts == [CMTimeRange(start: frames(7), end: frames(13))])
        #expect(plan.removedDuration == frames(6))
    }

    @Test func shortPausesStay() {
        let pattern = "#####......#####"  // 6 quiet frames; minus padding leaves 2 < 5.
        let p = project(pattern)
        #expect(SilencePlan.make(for: p, levels: [p.assets[0].id: levels(pattern)], settings: settings).isEmpty)
    }

    @Test func quietStartAndEndAreCutCompletely() {
        let pattern = "........#####........"
        let p = project(pattern)
        let plan = SilencePlan.make(for: p, levels: [p.assets[0].id: levels(pattern)], settings: settings)
        #expect(plan.timelineCuts == [
            CMTimeRange(start: .zero, end: frames(6)),
            CMTimeRange(start: frames(15), end: frames(21)),
        ])
    }

    @Test func applyingKeepsSourceContinuityAndTheClip() throws {
        let pattern = "#####..........##########"
        var p = project(pattern)
        let original = p.timeline.clips[0].id
        let plan = SilencePlan.make(for: p, levels: [p.assets[0].id: levels(pattern)], settings: settings)
        p.apply(plan)
        #expect(p.timeline.clips.count == 2)
        #expect(p.timeline.clips[0].id == original)
        #expect(p.timeline.clips[0].sourceRange == CMTimeRange(start: .zero, end: frames(7)))
        #expect(p.timeline.clips[1].sourceRange == CMTimeRange(start: frames(13), end: frames(25)))
        #expect(p.duration == frames(25) - plan.removedDuration)
    }

    @Test func followsClipsAfterEdits() {
        let pattern = "#####..........##########"
        var p = project(pattern)
        p.timeline.split(at: frames(10))  // Cut in the middle of the pause.
        let plan = SilencePlan.make(for: p, levels: [p.assets[0].id: levels(pattern)], settings: settings)
        // Each half's quiet part touches the cut, so that side gets no padding.
        #expect(plan.timelineCuts == [
            CMTimeRange(start: frames(7), end: frames(10)),
            CMTimeRange(start: frames(10), end: frames(13)),
        ].filter { $0.duration >= frames(5) })
        p.apply(plan)
        #expect(p.duration == frames(25) - plan.removedDuration)
    }

    @Test func clipsWithoutLevelsOrAllQuietAreLeftAlone() {
        let p = project(".........")
        #expect(SilencePlan.make(for: p, levels: [:], settings: settings).isEmpty)
        #expect(SilencePlan.make(for: p, levels: [p.assets[0].id: levels(".........")], settings: settings).isEmpty)
    }

    @Test func captionsInCutPartsDisappear() {
        let pattern = "#####..........##########"
        var p = project(pattern)
        let id = p.assets[0].id
        p.transcripts[id] = Transcript(language: .english, words: [
            Word(text: "hello", start: .zero, duration: frames(5)),
            Word(text: "um", start: frames(9), duration: frames(2)),
            Word(text: "world", start: frames(15), duration: frames(5)),
        ])
        p.apply(SilencePlan.make(for: p, levels: [id: levels(pattern)], settings: settings))
        #expect(CaptionLayout.timelineWords(in: p).map(\.text) == ["hello", "world"])
    }

    @Test func suggestedThresholdSitsBetweenNoiseAndSpeech() {
        let room = AudioLevels(decibels: Array(repeating: -60, count: 50) + Array(repeating: -15, count: 50))
        let threshold = room.suggestedThreshold
        #expect(threshold > -60 && threshold < -15)
    }
}
