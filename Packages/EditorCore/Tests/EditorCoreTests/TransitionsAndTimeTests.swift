import CoreGraphics
import CoreMedia
import Foundation
import Testing

@testable import EditorCore

private func t(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600).snappedToFrame() }

private func video(_ name: String, seconds: Int64 = 10, frameRate: Double? = nil) -> MediaAsset {
    MediaAsset(
        url: URL(fileURLWithPath: "/tmp/\(name)"), name: name, duration: CMTime(value: seconds, timescale: 1),
        displaySize: CGSize(width: 1080, height: 1920), hasAudio: true, frameRate: frameRate)
}

/// Clips A (10 s) and B (10 s), back to back.
private func twoFiles() -> (Project, MediaAsset.ID, MediaAsset.ID) {
    var p = Project()
    let a = p.addAsset(video("a.mov"))
    let b = p.addAsset(video("b.mov"))
    p.appendClip(of: a)
    p.appendClip(of: b)
    return (p, a, b)
}

private func lengths(_ p: Project) -> [Double] { p.timeline.clips.map { ($0.duration.seconds * 10).rounded() / 10 } }

struct TransitionTests {
    @Test func aTransitionPlaysHalfBeforeAndHalfAfterTheCut() {
        var (p, _, _) = twoFiles()
        let first = p.timeline.clips[0].id
        let did1 = p.setTransition(ClipTransition(kind: .dissolve), after: first)
        #expect(did1)
        let spans = p.timeline.transitionSpans
        #expect(spans.count == 1)
        #expect(spans[0].cut == t(10))
        // Half a second is 15 frames; an even 14 are used, 7 on each side.
        #expect(spans[0].range.duration == CMTime(value: 14, timescale: 30))
        #expect(spans[0].range.start < t(10) && spans[0].range.end > t(10))
        #expect((spans[0].cut - spans[0].range.start) == (spans[0].range.end - spans[0].cut))
        // The Short keeps its length.
        #expect(p.duration == t(20))
        #expect(spans[0].progress(at: spans[0].range.start) == 0)
        #expect(abs(spans[0].progress(at: t(10)) - 0.5) < 0.001)
    }

    @Test func lengthIsAnEvenNumberOfFramesInRange() {
        #expect(ClipTransition.allowed(t(0.5)).value == 14)
        #expect(ClipTransition.allowed(t(0.05)) == ClipTransition.minimumDuration)
        #expect(ClipTransition.allowed(t(9)) == ClipTransition.maximumDuration)
        #expect(ClipTransition(kind: .wipe, duration: t(1)).duration == t(1))
    }

    @Test func noTransitionAfterTheLastClip() {
        var (p, _, _) = twoFiles()
        let last = p.timeline.clips[1].id
        let did2 = p.setTransition(ClipTransition(), after: last)
        #expect(!did2)
        p.timeline.clips[1].transitionOut = ClipTransition()
        #expect(p.timeline.transitionSpans.isEmpty)
        #expect(p.transitionCount == 0)
    }

    @Test func aShortClipMakesTheTransitionShorter() {
        var (p, _, _) = twoFiles()
        p.timeline.split(at: t(10.2)) // B: 0.2 s (6 frames) + 9.8 s
        p.setTransition(ClipTransition(kind: .slide, duration: t(1)), after: p.timeline.clips[0].id)
        p.setTransition(ClipTransition(kind: .slide, duration: t(1)), after: p.timeline.clips[1].id)
        let spans = p.timeline.transitionSpans
        #expect(spans.count == 2)
        // Each takes at most half of the six-frame clip, so they meet but don't overlap.
        #expect(spans[0].range.end == t(10.1))
        #expect(spans[1].range.start == t(10.1))
        #expect(spans[0].half == CMTime(value: 3, timescale: 30))
    }

    @Test func splittingKeepsTheTransitionAtTheCut() {
        var (p, _, _) = twoFiles()
        p.setTransition(ClipTransition(kind: .zoom), after: p.timeline.clips[0].id)
        p.timeline.split(at: t(4))
        #expect(p.timeline.clips[0].transitionOut == nil)
        #expect(p.timeline.clips[1].transitionOut?.kind == .zoom)
        #expect(p.timeline.transitionSpans.map(\.cut) == [t(10)])
    }

    @Test func everyCutAndNone() {
        var (p, _, _) = twoFiles()
        p.timeline.split(at: t(4))
        p.setTransitionOnEveryCut(ClipTransition(kind: .whip))
        #expect(p.transitionCount == 2)
        #expect(p.timeline.clips.last?.transitionOut == nil)
        p.setTransitionOnEveryCut(nil)
        #expect(p.transitionCount == 0)
    }

    @Test func nearestCut() {
        var (p, _, _) = twoFiles()
        p.timeline.split(at: t(4))
        #expect(p.timeline.clipBeforeCut(nearest: t(1)) == p.timeline.clips[0].id)
        #expect(p.timeline.clipBeforeCut(nearest: t(8)) == p.timeline.clips[1].id)
        var one = Project()
        let a = one.addAsset(video("a.mov"))
        one.appendClip(of: a)
        #expect(one.timeline.clipBeforeCut(nearest: t(1)) == nil)
    }

    @Test func transitionsAreSaved() throws {
        var (p, _, _) = twoFiles()
        p.setTransition(ClipTransition(kind: .throughWhite, duration: t(0.8)), after: p.timeline.clips[0].id)
        let back = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(p))
        #expect(back == p)
        #expect(back.timeline.clips[0].transitionOut?.kind == .throughWhite)
    }
}

struct PictureFadeTests {
    @Test func opacityIsSavedAndOlderFilesAreSolid() throws {
        let old = Data(#"{"offsetX":0.1,"offsetY":0,"scale":1.5,"rotation":0}"#.utf8)
        #expect(try JSONDecoder().decode(Placement.self, from: old).opacity == 1)
        let p = Placement(scale: 2, opacity: 0.4)
        #expect(try JSONDecoder().decode(Placement.self, from: JSONEncoder().encode(p)) == p)
        #expect(Placement(opacity: 3).normalized.opacity == 1)
        #expect(!Placement(opacity: 0.5).isIdentity)
    }

    @Test func opacityMovesBetweenKeyframes() {
        var clip = Clip(assetID: UUID(), sourceStart: .zero, duration: t(4))
        clip.keyframes = [
            Keyframe(time: .zero, placement: Placement(opacity: 0), easing: .linear),
            Keyframe(time: t(2), placement: Placement(opacity: 1), easing: .linear),
        ]
        #expect(abs(clip.placement(atSourceTime: t(1)).opacity - 0.5) < 0.001)
    }

    @Test func pictureFadesInAndOut() {
        var clip = Clip(assetID: UUID(), sourceStart: .zero, duration: t(4))
        #expect(clip.pictureFade(atOffset: .zero) == 1)
        clip.pictureFadeIn = t(1)
        clip.pictureFadeOut = t(2)
        #expect(clip.pictureFade(atOffset: .zero) < 0.05)
        #expect(abs(clip.pictureFade(atOffset: t(0.5)) - 0.5) < 0.05)
        #expect(clip.pictureFade(atOffset: t(1.5)) == 1)
        #expect(abs(clip.pictureFade(atOffset: t(3)) - 0.5) < 0.05)
        #expect(clip.pictureFade(atOffset: t(4)) == 0)
        // Cut short at the end of the Short, it still fades out before its end.
        #expect(clip.pictureFade(atOffset: t(2), length: t(2)) == 0)
    }

    @Test func splitKeepsTheFadeInFirstAndTheFadeOutLast() {
        var (p, a, _) = twoFiles()
        let id = p.addOverlay(of: a, at: t(2))!
        p.updateOverlay(id) {
            $0.clip.pictureFadeIn = t(0.5); $0.clip.pictureFadeOut = t(0.5)
        }
        let second = p.splitOverlay(id, at: t(4))!
        #expect(p.overlay(id: id)?.clip.pictureFadeIn == t(0.5) && p.overlay(id: id)?.clip.pictureFadeOut == .zero)
        #expect(p.overlay(id: second)?.clip.pictureFadeIn == .zero && p.overlay(id: second)?.clip.pictureFadeOut == t(0.5))
    }
}

struct FreezeFrameTests {
    @Test func freezeCutsTheClipAndHoldsThePicture() {
        var (p, a, _) = twoFiles()
        let id = p.addFreezeFrame(at: t(4))
        #expect(lengths(p) == [4, 3, 6, 10])
        let frozen = p.timeline.clips[1]
        #expect(frozen.id == id && frozen.isFrozen && frozen.assetID == a)
        #expect(frozen.sourceStart == t(4))
        #expect(frozen.sourceTime(atOffset: t(2)) == t(4))
        #expect(frozen.sourceDuration == .zero)
        #expect(frozen.effectiveVolume == 0)
        // The clip carries on where it stopped.
        #expect(p.timeline.clips[2].sourceStart == t(4))
    }

    @Test func freezeOnACutGoesBeforeTheClipAndAtTheEndAfterIt() {
        var (p, _, b) = twoFiles()
        p.addFreezeFrame(at: t(10))
        #expect(lengths(p) == [10, 3, 10])
        #expect(p.timeline.clips[1].assetID == b && p.timeline.clips[1].sourceStart == .zero)
        p.addFreezeFrame(at: p.duration)
        #expect(lengths(p) == [10, 3, 10, 3])
        #expect(p.timeline.clips[3].sourceStart == t(10) - .oneFrame)
    }

    @Test func aFreezeFrameCanBeAnyLengthButHasNoSpeed() {
        var (p, _, _) = twoFiles()
        let id = p.addFreezeFrame(at: t(4))!
        let did3 = p.trimClip(id, edge: .end, by: t(20))
        #expect(did3)
        #expect(p.timeline.clips[1].duration == t(23))
        let did4 = p.trimClip(id, edge: .start, by: t(-5))
        #expect(did4)
        #expect(p.timeline.clips[1].sourceStart == t(4))
        p.setSpeed(2, for: id)
        #expect(p.timeline.clips[1].speed == 1 && p.timeline.clips[1].duration == t(28))
        // Splitting gives two freeze frames of the same picture.
        p.timeline.split(at: t(6))
        #expect(p.timeline.clips[1].isFrozen && p.timeline.clips[2].isFrozen && p.timeline.clips[2].sourceStart == t(4))
        // No freeze frame of a freeze frame.
        let again = p.addFreezeFrame(at: t(5))
        #expect(again == nil)
    }

    @Test func theMotionStopsWithThePicture() {
        var (p, _, _) = twoFiles()
        p.timeline.clips[0].keyframes = [
            Keyframe(time: .zero, placement: Placement(scale: 1), easing: .linear),
            Keyframe(time: t(10), placement: Placement(scale: 2), easing: .linear),
        ]
        p.addFreezeFrame(at: t(5))
        let frozen = p.timeline.clips[1]
        #expect(frozen.keyframes.isEmpty)
        #expect(abs(frozen.placement.scale - 2.0.squareRoot()) < 0.01)
    }

    @Test func removePausesLeavesFreezeFramesAlone() {
        var (p, a, _) = twoFiles()
        let id = p.addFreezeFrame(at: t(4))!
        let levels = [a: AudioLevels(decibels: Array(repeating: -80, count: 300))]
        let plan = SilencePlan.make(for: p, levels: levels, settings: SilenceSettings())
        #expect(plan.sourceCuts[id] == nil)
    }
}

struct InstantReplayTests {
    @Test func theClipPlaysAgainSlower() {
        var (p, a, _) = twoFiles()
        let ids = p.addInstantReplay(of: CMTimeRange(start: .zero, duration: t(10)))
        #expect(lengths(p) == [10, 20, 10])
        #expect(ids == [p.timeline.clips[1].id])
        #expect(p.timeline.clips[1].assetID == a && p.timeline.clips[1].speed == 0.5)
        #expect(p.timeline.clips[1].sourceRange == p.timeline.clips[0].sourceRange)
    }

    @Test func aPartPlaysAgainAndTheTransitionMovesBehindIt() {
        var (p, _, _) = twoFiles()
        p.setTransition(ClipTransition(), after: p.timeline.clips[0].id)
        p.addInstantReplay(of: CMTimeRange(start: t(8), end: t(10)))
        #expect(lengths(p) == [8, 2, 4, 10])
        #expect(p.timeline.clips[2].sourceStart == t(8))
        #expect(p.timeline.clips[1].transitionOut == nil && p.timeline.clips[2].transitionOut != nil)
    }
}

struct SpeedRampTests {
    /// A at 1× for 4 s, its middle 2 s at half speed (4 s long), then the rest.
    private func slowMiddle() -> Project {
        var (p, _, _) = twoFiles()
        p.setSpeed(0.5, in: CMTimeRange(start: t(4), end: t(6)))
        return p
    }

    @Test func speedChangesInStepsAtBothEndsOfThePart() {
        let p = slowMiddle()
        #expect(lengths(p) == [4, 4, 4, 10])
        #expect(p.timeline.speedRampFrames(afterClipAt: 0) == 15)
        #expect(p.timeline.speedRampFrames(afterClipAt: 1) == 15)
        // Not into another file.
        #expect(p.timeline.speedRampFrames(afterClipAt: 2) == 0)
        #expect(p.timeline.hasSpeedRamp(atClip: 1) && !p.timeline.hasSpeedRamp(atClip: 3))

        for index in 0..<3 {
            let clip = p.timeline.clips[index]
            let segments = p.timeline.speedSegments(forClipAt: index)
            // They fill the clip's time exactly and follow on in the file.
            #expect(segments.reduce(CMTime.zero) { $0 + $1.duration } == clip.duration)
            for (a, b) in zip(segments, segments.dropFirst()) { #expect(a.source.end == b.source.start) }
            #expect(segments.count == (index == 1 ? 11 : 6))
        }
        // Across each cut the file carries straight on.
        let first = p.timeline.speedSegments(forClipAt: 0), middle = p.timeline.speedSegments(forClipAt: 1), last = p.timeline.speedSegments(forClipAt: 2)
        #expect(abs((first.last!.source.end - middle.first!.source.start).seconds) < 0.001)
        #expect(abs((middle.last!.source.end - last.first!.source.start).seconds) < 0.001)
        #expect(first.first!.source.start == .zero)
        #expect(abs(last.last!.source.end.seconds - 10) < 0.001)
        // The speeds go down step by step, from just under 1 to just over a half.
        let speeds = (first.dropFirst() + middle.prefix(5)).map(\.speed)
        #expect(speeds == speeds.sorted(by: >))
        #expect(speeds.first! < 1 && speeds.first! > 0.9 && speeds.last! > 0.5 && speeds.last! < 0.6)
    }

    @Test func noStepsWhenSwitchedOffOrAcrossATransition() {
        var p = slowMiddle()
        p.timeline.clips[1].smoothSpeed = false
        #expect(p.timeline.speedRampFrames(afterClipAt: 0) == 0)
        #expect(p.timeline.speedSegments(forClipAt: 1) == [SpeedSegment(source: p.timeline.clips[1].sourceRange, duration: t(4))])
        p.timeline.clips[1].smoothSpeed = true
        p.setTransition(ClipTransition(), after: p.timeline.clips[0].id)
        #expect(p.timeline.speedRampFrames(afterClipAt: 0) == 0)
        #expect(p.timeline.speedRampFrames(afterClipAt: 1) == 15)
    }

    @Test func aShortPartGetsAShorterChange() {
        var (p, _, _) = twoFiles()
        p.setSpeed(2, in: CMTimeRange(start: t(4), end: t(4.4))) // 12 frames of file → 6 frames
        #expect(p.timeline.clips[1].duration == CMTime(value: 6, timescale: 30))
        #expect(p.timeline.speedRampFrames(afterClipAt: 0) == 3)
        let segments = p.timeline.speedSegments(forClipAt: 1)
        #expect(segments.reduce(CMTime.zero) { $0 + $1.duration } == p.timeline.clips[1].duration)
    }

    @Test func slowMotionFootageStartsSlowedDown() {
        var p = Project()
        let slow = p.addAsset(video("slow.mov", seconds: 4, frameRate: 120))
        let normal = p.addAsset(video("normal.mov", seconds: 4, frameRate: 60))
        p.appendClip(of: slow)
        p.appendClip(of: normal)
        #expect(p.timeline.clips[0].speed == 0.25 && p.timeline.clips[0].duration == t(16))
        #expect(p.timeline.clips[0].sourceDuration == t(4))
        #expect(p.timeline.clips[1].speed == 1)
        #expect(p.asset(id: normal)?.smoothestSlowSpeed == 0.5)
        #expect(video("x.mov", frameRate: 240).defaultSpeed == 0.25)
    }
}

struct BackwardsTests {
    private func withCopy(of range: CMTimeRange? = nil) -> (Project, MediaAsset.ID, MediaAsset.ID) {
        var (p, a, _) = twoFiles()
        let range = range ?? CMTimeRange(start: .zero, duration: t(10))
        var copy = video("a backwards.mov", seconds: Int64(range.duration.seconds))
        copy.reversedFrom = ReversedSource(assetID: a, range: range)
        let r = p.addAsset(copy)
        return (p, a, r)
    }

    @Test func aClipTurnsRoundAndBack() {
        var (p, a, r) = withCopy()
        p.timeline.split(at: t(4))
        let id = p.timeline.clips[1].id // shows 4…10 of A
        p.timeline.clips[1].keyframes = [Keyframe(time: t(5), placement: Placement(scale: 2))]
        #expect(!p.isReversed(p.timeline.clips[1]))
        let did5 = p.flipDirection(of: id)
        #expect(did5)
        let turned = p.timeline.clips[1]
        #expect(turned.assetID == r && p.isReversed(turned))
        // 4…10 of the original is 0…6 of the copy, and second 5 is second 5 from its end.
        #expect(turned.sourceStart == .zero && turned.duration == t(6))
        #expect(turned.keyframes[0].time == t(5))
        let did6 = p.flipDirection(of: id)
        #expect(did6)
        #expect(p.timeline.clips[1].assetID == a && p.timeline.clips[1].sourceStart == t(4))
    }

    @Test func withoutACopyThereIsNothingToTurnTo() {
        var (p, _, _) = twoFiles()
        let did7 = p.flipDirection(of: p.timeline.clips[0].id)
        #expect(!did7)
        #expect(p.counterpart(for: p.timeline.clips[0]) == nil)
    }

    @Test func aCopyOfAnotherPartDoesNotCount() {
        var (p, _, _) = withCopy(of: CMTimeRange(start: t(5), duration: t(5)))
        #expect(p.counterpart(for: p.timeline.clips[0]) == nil)
        p.timeline.split(at: t(6))
        let did8 = p.flipDirection(of: p.timeline.clips[1].id)
        #expect(did8)
        #expect(p.timeline.clips[1].sourceStart == .zero)
    }

    @Test func longFilesAreTurnedAroundInPart() {
        var p = Project()
        let long = p.addAsset(video("long.mov", seconds: 300))
        p.appendClip(of: long, part: CMTimeRange(start: t(100), duration: t(10)))
        #expect(p.partToReverse(for: p.timeline.clips[0]) == CMTimeRange(start: t(97), end: t(113)))
        let (q, _, _) = twoFiles()
        #expect(q.partToReverse(for: q.timeline.clips[0]) == CMTimeRange(start: .zero, duration: t(10)))
    }

    @Test func reversedSourceIsSaved() throws {
        let (p, _, r) = withCopy()
        let back = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(p))
        #expect(back.asset(id: r)?.reversedFrom == p.asset(id: r)?.reversedFrom)
    }
}

struct SoundCrossfadeTests {
    /// A 2…6 s of a.mov, then B 2…6 s of b.mov, with a dissolve of `frames` frames.
    private func trimmed(frames: Int64 = 30) -> Project {
        var (p, a, b) = twoFiles()
        p.timeline.clips = [Clip(assetID: a, sourceStart: t(2), duration: t(4)), Clip(assetID: b, sourceStart: t(2), duration: t(4))]
        p.setTransition(ClipTransition(kind: .dissolve, duration: CMTime(value: frames, timescale: Project.frameRate)), after: p.timeline.clips[0].id)
        return p
    }

    @Test func bothClipsAreHeardAcrossATransition() throws {
        let p = trimmed()
        let fade = try #require(p.soundCrossfades.first)
        #expect(fade.span.cut == t(4))
        // The new clip's sound starts half a second early, the old one's goes on half a second.
        #expect(fade.incomingSource == CMTimeRange(start: t(1.5), duration: t(0.5)))
        #expect(fade.outgoingSource == CMTimeRange(start: t(6), duration: t(0.5)))
        let envelope = AudioMix.storylineEnvelope(p.timeline.clips, crossfades: p.soundCrossfades)
        #expect(abs(AudioMix.volume(at: t(3.5), in: envelope) - 1) < 0.001)
        #expect(abs(AudioMix.volume(at: t(3.8), in: envelope) - 0.7) < 0.001)
        #expect(abs(AudioMix.volume(at: t(4.2), in: envelope) - 0.7) < 0.001)
        #expect(abs(AudioMix.volume(at: t(4.5), in: envelope) - 1) < 0.001)
    }

    @Test func soundCutsWhereThereIsNothingToBorrow() {
        var p = trimmed()
        // The new clip starts at the very start of its file: nothing before it.
        p.timeline.clips[1].sourceStart = .zero
        #expect(p.soundCrossfades.isEmpty)
        // Faded or muted sound also just cuts.
        p = trimmed(); p.timeline.clips[0].fadeOut = t(0.3)
        #expect(p.soundCrossfades.isEmpty)
        p = trimmed(); p.timeline.clips[1].volume = 0
        #expect(p.soundCrossfades.isEmpty)
        #expect(AudioMix.storylineEnvelope(p.timeline.clips, crossfades: p.soundCrossfades) == AudioMix.storylineEnvelope(p.timeline.clips))
    }

    @Test func fasterClipsBorrowMoreOfTheirFile() throws {
        var p = trimmed()
        // 0…8 s of a.mov played in 4 s.
        p.timeline.clips[0].sourceStart = .zero
        p.timeline.clips[0].speed = 2
        let fade = try #require(p.soundCrossfades.first)
        #expect(fade.outgoingSource.duration == t(1))
    }
}
