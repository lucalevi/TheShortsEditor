import CoreGraphics
import CoreMedia
import Foundation
import Testing

@testable import EditorCore

private func t(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600).snappedToFrame() }

private func video(_ name: String, seconds: Int64 = 10) -> MediaAsset {
    MediaAsset(
        url: URL(fileURLWithPath: "/tmp/\(name)"), name: name, duration: CMTime(value: seconds, timescale: 1),
        displaySize: CGSize(width: 1080, height: 1920), hasAudio: true)
}

private func song(_ name: String = "song.m4a", seconds: Int64 = 60) -> MediaAsset {
    MediaAsset(
        url: URL(fileURLWithPath: "/tmp/\(name)"), name: name, duration: CMTime(value: seconds, timescale: 1),
        displaySize: .zero, hasAudio: true, hasVideo: false)
}

/// Three 10 s files, each used whole, and a song.
private func shortWithSong(songSeconds: Int64 = 60) -> Project {
    var p = Project()
    for name in ["a.mov", "b.mov", "c.mov"] { p.appendClip(of: p.addAsset(video(name))) }
    p.setMusic(p.addAsset(song(seconds: songSeconds)))
    return p
}

private func near(_ a: CMTime, _ b: CMTime, _ tolerance: Double = 0.02) -> Bool { abs((a - b).seconds) <= tolerance }

// MARK: - Beats

struct BeatTests {
    @Test func moodMusicKnowsItsBeats() {
        let beats = MusicMood.playful.beats(upTo: CMTime(value: 10, timescale: 1))
        // 128 beats a minute: one every 0.46875 s, a bar every four.
        #expect(beats.count == 22)
        #expect(near(beats[1].time, CMTime(seconds: 0.46875, preferredTimescale: 48_000), 0.0001))
        #expect(beats[0].isBarStart && !beats[1].isBarStart && beats[4].isBarStart)
    }

    @Test func beatsAreFoundInASteadyPulse() {
        // 100 onsets a second; a strong onset on every beat at 120 bpm from 0.3 s, stronger bass every fourth beat from the second.
        let rate = 100.0, seconds = 20.0
        var onsets = [Float](repeating: 0.02, count: Int(rate * seconds))
        var bass = [Float](repeating: 0, count: onsets.count)
        var beat = 0
        var time = 0.3
        while time < seconds {
            let i = Int((time * rate).rounded())
            if i < onsets.count {
                onsets[i] = 1
                bass[i] = beat % 4 == 1 ? 1 : 0.2
            }
            beat += 1
            time += 0.5
        }
        let beats = BeatFinder.beats(onsets: onsets, bass: bass, rate: rate, length: CMTime(value: 20, timescale: 1))
        #expect(beats.count >= 38 && beats.count <= 40)
        guard beats.count > 5 else { return }
        #expect(near(beats[0].time, t(0.3), 0.03))
        #expect(near(beats[4].time - beats[0].time, t(2), 0.05))
        // Bars begin on the strong bass: 0.8 s, 2.8 s…
        let bars = beats.filter(\.isBarStart)
        #expect(near(bars[0].time, t(0.8), 0.03))
        #expect(near(bars[1].time, t(2.8), 0.05))
    }

    @Test func silenceHasNoBeats() {
        let beats = BeatFinder.beats(
            onsets: [Float](repeating: 0, count: 2000), bass: [Float](repeating: 0, count: 2000), rate: 100, length: CMTime(value: 20, timescale: 1))
        #expect(beats.isEmpty)
    }

    @Test func beatsArePlacedOnTheTimelineWhereTheMusicPlays() {
        var p = shortWithSong()
        p.music?.beats = (0..<120).map { Beat(time: CMTime(value: Int64($0), timescale: 2), isBarStart: $0 % 4 == 0) }
        #expect(p.timelineBeats.first?.time == .zero)
        // Starting the song 1.25 s in moves every beat back by as much.
        p.setMusicStart(t(1.25))
        let shifted = p.timelineBeats
        #expect(
            near(shifted.first?.time ?? .invalid, CMTime(value: 1, timescale: 2) - p.music!.sourceStart + CMTime(value: 1, timescale: 1)),
            "\(shifted.prefix(2)) \(p.music!.sourceStart.seconds)")
        #expect(shifted[0].indexInBar == 1 || shifted[0].isBarStart == false)
        // Starting the music later on the timeline moves them forward.
        p.setMusicStart(.zero)
        p.setMusicTimelineStart(t(4))
        #expect(p.timelineBeats.first?.time == t(4))
        #expect(p.timelineBeats.allSatisfy { $0.time >= t(4) && $0.time < p.duration })
    }

    @Test func beatsCanBeAddedAndRemovedByHand() {
        var p = shortWithSong()
        #expect(!p.hasBeats)
        let added = p.addBeat(atTimeline: t(2))
        #expect(added)
        #expect(p.music?.showsBeats == true)
        #expect(p.timelineBeats.map(\.time) == [t(2)])
        // Not twice in the same place.
        let again = p.addBeat(atTimeline: t(2))
        #expect(!again)
        let removed = p.removeBeat(nearTimeline: t(2.05))
        #expect(removed)
        #expect(p.timelineBeats.isEmpty)
        let removedAgain = p.removeBeat(nearTimeline: t(2))
        #expect(!removedAgain)
    }

    @Test func beatsAreSnapTargetsOnlyWhileShown() {
        var p = shortWithSong()
        p.music?.beats = [Beat(time: t(3.3))]
        #expect(!Snapping.targets(in: p, playhead: nil).contains(t(3.3)))
        p.music?.showsBeats = true
        #expect(Snapping.targets(in: p, playhead: nil).contains(t(3.3)))
    }

    @Test func beatsAndPlacementSurviveSaving() throws {
        var p = shortWithSong()
        p.music?.beats = [Beat(time: t(0.5), isBarStart: true), Beat(time: t(1))]
        p.music?.showsBeats = true
        p.music?.loops = true
        p.setMusicTimelineStart(t(2))
        let data = try JSONEncoder().encode(p.music)
        let back = try JSONDecoder().decode(BackgroundMusic.self, from: data)
        #expect(back == p.music)
    }
}

// MARK: - Music placed later or looped

struct MusicPlacementTests {
    @Test func musicCanStartLater() {
        var p = shortWithSong()
        p.setMusicTimelineStart(t(5))
        #expect(p.musicRange == CMTimeRange(start: t(5), end: t(30)))
        // Never at or past the end of the Short.
        p.setMusicTimelineStart(t(40))
        #expect(p.musicRange?.start == t(29))
    }

    @Test func aShortSongLoopsToTheEnd() {
        var p = shortWithSong(songSeconds: 12)
        p.setMusicStart(t(2))
        #expect(p.musicRange?.duration == t(10))
        p.music?.loops = true
        #expect(p.musicRange == CMTimeRange(start: .zero, end: t(30)))
        let passes = p.musicPasses
        #expect(passes.count == 3)
        #expect(passes[0].source == CMTimeRange(start: t(2), end: t(12)))
        #expect(passes[1].start == t(10) && passes[1].source.start == .zero)
        #expect(passes[2].start == t(22) && passes[2].source.duration == t(8))
        #expect(near(p.songTime(atTimeline: t(23))!, t(1)))
    }

    @Test func fadesAndDuckingFollowWhereTheMusicStarts() {
        var p = shortWithSong()
        p.setMusicTimelineStart(t(6))
        let envelope = AudioMix.musicEnvelope(for: p, speech: [])
        #expect(envelope.first?.time == t(6))
        #expect(envelope.first?.volume == 0)
        #expect(AudioMix.volume(at: t(7), in: envelope) == p.music!.volume)
    }

    @Test func moodMusicThatStartsLaterStillEndsOnABar() {
        var p = shortWithSong()
        p.music?.mood = .upbeat
        p.setMusicTimelineStart(t(3))
        p.fitMoodMusic()
        let bar = MusicMood.upbeat.barLength.seconds
        let played = p.music!.sourceStart.seconds + 27
        #expect(abs(played / bar - (played / bar).rounded()) < 0.001)
    }
}

// MARK: - Cut to the Beat

struct CutToBeatTests {
    /// Beats every 0.5 s from 0.2 s, bars every four.
    private func steady(_ p: inout Project) {
        p.music?.beats = (0..<110).map { Beat(time: CMTime(seconds: 0.2 + Double($0) * 0.5, preferredTimescale: 600), isBarStart: $0 % 4 == 0) }
    }

    @Test func everyCutLandsOnABeat() {
        var p = Project()
        for name in ["a.mov", "b.mov", "c.mov"] { p.appendClip(of: p.addAsset(video(name))) }
        p.trimClip(p.timeline.clips[0].id, edge: .end, by: t(-7.1)) // 2.9 s
        p.trimClip(p.timeline.clips[1].id, edge: .end, by: t(-6.0)) // 4 s
        p.trimClip(p.timeline.clips[2].id, edge: .end, by: t(-8.3)) // 1.7 s
        p.setMusic(p.addAsset(song()))
        steady(&p)
        let moved = p.cutToBeat(.everyBeat)
        // 2.9 → 2.7; 2.7 + 4 = 6.7 is on a beat already; 6.7 + 1.7 = 8.4 → 8.2.
        #expect(moved == 2)
        let beats = Set(p.timelineBeats(through: Project.maxDuration).map { $0.time.snappedToFrame() })
        var start = CMTime.zero
        for clip in p.timeline.clips {
            start = start + clip.duration
            #expect(beats.contains(start))
        }
        #expect(p.timeline.clips[0].duration == t(2.7))
        #expect(p.duration == t(8.2))
    }

    @Test func barsMakeLongerCuts() {
        var p = shortWithSong()
        steady(&p)
        p.cutToBeat(.everyBar)
        // Bars at 0.2, 2.2, … 8.2, 10.2: the whole 10 s file can't grow to 10.2, so it ends at 8.2.
        #expect(p.timeline.clips[0].duration == t(8.2))
        let bars = Set(p.timelineBeats.filter { $0.isBarStart }.map { $0.time.snappedToFrame() })
        #expect(bars.contains(p.timeline.clips[0].duration))
    }

    @Test func aClipCanNotGrowPastItsFile() {
        var p = shortWithSong()
        steady(&p)
        // The first clip is the whole 10 s file: its cut can only move earlier, to 9.7.
        p.cutToBeat(.everyBeat)
        #expect(p.timeline.clips[0].duration == t(9.7))
    }

    @Test func withoutBeatsNothingChanges() {
        var p = shortWithSong()
        let before = p.timeline
        let moved = p.cutToBeat(.everyBeat)
        #expect(moved == 0)
        #expect(p.timeline == before)
    }
}

// MARK: - Speed curves

struct SpeedCurveTests {
    private func oneClip() -> Project {
        var p = Project()
        p.appendClip(of: p.addAsset(video("a.mov", seconds: 20)))
        p.trimClip(p.timeline.clips[0].id, edge: .end, by: t(-14)) // 6 s of the file
        return p
    }

    @Test func aCurveKeepsTheFootageAndChangesTheLength() {
        var p = oneClip()
        let id = p.timeline.clips[0].id
        p.setSpeedCurve(.bullet, for: id)
        let clip = p.timeline.clips[0]
        #expect(clip.speedCurve == SpeedCurve(.bullet))
        // Bullet is slow on average, so the clip gets longer, showing about the same 6 s.
        #expect(clip.duration > t(8.5))
        #expect(abs(clip.sourceDuration.seconds - 6) < 0.15)
        p.setSpeedCurve(nil, for: id)
        #expect(abs(p.timeline.clips[0].duration.seconds - 6) < 0.15)
    }

    @Test func mappingGoesBothWays() {
        var p = oneClip()
        p.setSpeedCurve(.montage, for: p.timeline.clips[0].id)
        let clip = p.timeline.clips[0]
        for seconds in stride(from: 0.0, through: clip.duration.seconds, by: 0.37) {
            let offset = CMTime(seconds: seconds, preferredTimescale: 600)
            let back = clip.timelineOffset(ofSourceTime: clip.sourceTime(atOffset: offset))
            #expect(abs((back - offset).seconds) < 0.001)
        }
        // Montage starts fast: the first second shows more than a second of the file.
        #expect(clip.sourceTime(atOffset: t(0.3)).seconds > 0.45)
    }

    @Test func segmentsFillTheClipAndFollowOnInTheFile() {
        var p = oneClip()
        p.setSpeedCurve(.hero, for: p.timeline.clips[0].id)
        let segments = p.timeline.speedSegments(forClipAt: 0)
        let clip = p.timeline.clips[0]
        #expect(segments.reduce(CMTime.zero) { $0 + $1.duration } == clip.duration)
        for (a, b) in zip(segments, segments.dropFirst()) { #expect(abs((a.source.end - b.source.start).seconds) < 0.0001) }
        #expect(abs((segments.last!.source.end - clip.sourceRange.end).seconds) < 0.001)
        // Slow in the middle, fast at the ends.
        #expect(segments[segments.count / 2].speed < 0.5)
        #expect(segments[0].speed > 1.5)
    }

    @Test func splittingKeepsEachHalfsPartOfTheShape() {
        var p = oneClip()
        p.setSpeedCurve(.flashIn, for: p.timeline.clips[0].id)
        let whole = p.timeline.clips[0]
        let middle = CMTimeMultiplyByRatio(whole.duration, multiplier: 1, divisor: 2).snappedToFrame()
        p.timeline.split(at: middle)
        let first = p.timeline.clips[0], second = p.timeline.clips[1]
        #expect(first.speedCurve?.from == 0 && second.speedCurve?.to == 1)
        #expect(first.speedCurve?.to == second.speedCurve?.from)
        // The second half carries on where the first stopped, at the settled speed.
        #expect(abs((first.sourceRange.end - second.sourceStart).seconds) < 0.001)
        #expect(second.speed(atOffset: .zero) < 1.2)
    }

    @Test func aCurveSurvivesSavingAndTurnsOffGradualSpeed() throws {
        var p = oneClip()
        p.setSpeedCurve(.jumpCut, for: p.timeline.clips[0].id)
        let data = try JSONEncoder().encode(p.timeline.clips[0])
        let back = try JSONDecoder().decode(Clip.self, from: data)
        #expect(back.speedCurve == SpeedCurve(.jumpCut))
        #expect(p.timeline.speedRampFrames(afterClipAt: 0) == 0)
    }

    @Test func picturesHaveNoCurve() {
        var p = Project()
        let picture = MediaAsset(
            url: URL(fileURLWithPath: "/tmp/p.jpg"), name: "p.jpg", duration: MediaAsset.imageDuration,
            displaySize: CGSize(width: 100, height: 100), hasAudio: false, isImage: true)
        p.appendClip(of: p.addAsset(picture))
        p.setSpeedCurve(.hero, for: p.timeline.clips[0].id)
        #expect(p.timeline.clips[0].speedCurve == nil)
    }
}

// MARK: - Clip animations

struct ClipAnimationTests {
    @Test func comingInStartsAwayAndEndsInPlace() {
        var clip = Clip(assetID: UUID(), sourceStart: .zero, duration: t(3))
        clip.animationIn = ClipAnimation(.slideUp)
        let first = clip.animationState(atOffset: .zero)!
        #expect(first.offsetY > 0.8)
        #expect(clip.animationState(atOffset: t(0.6)) == nil)
        clip.animationIn = ClipAnimation(.fade)
        #expect(clip.animationState(atOffset: .zero)!.opacity < 0.2)
    }

    @Test func goingOutEndsAway() {
        var clip = Clip(assetID: UUID(), sourceStart: .zero, duration: t(3))
        clip.animationOut = ClipAnimation(.zoom, duration: t(1))
        #expect(clip.animationState(atOffset: t(1.5)) == nil)
        let last = clip.animationState(atOffset: t(3) - .oneFrame)!
        #expect(last.scale > 1.4 && last.opacity < 0.1)
    }

    @Test func inAndOutShareAShortClip() {
        var clip = Clip(assetID: UUID(), sourceStart: .zero, duration: t(1))
        clip.animationIn = ClipAnimation(.pop, duration: t(1))
        clip.animationOut = ClipAnimation(.spin, duration: t(1))
        let lengths = clip.animationLengths
        #expect(near(lengths.in, t(0.5)) && near(lengths.out, t(0.5)))
    }

    @Test func everyMovementIsInPlaceAtTheEndOfComingIn() {
        for kind in MotionAnimation.allCases {
            let state = kind.state(progress: 1, entering: true)
            #expect(abs(state.scale - 1) < 0.001 && abs(state.opacity - 1) < 0.001 && abs(state.offsetX) < 0.001 && abs(state.offsetY) < 0.001)
            #expect(kind.state(progress: 0, entering: false).isIdentity)
        }
    }

    @Test func setAnimationClampsTheLengthAndSkipsSounds() {
        var p = Project()
        p.appendClip(of: p.addAsset(video("a.mov")))
        let id = p.timeline.clips[0].id
        p.setAnimation(ClipAnimation(.fade, duration: t(5)), entering: true, for: id)
        #expect(p.timeline.clips[0].animationIn?.duration == t(2))
        p.setAnimation(nil, entering: true, for: id)
        #expect(p.timeline.clips[0].animationIn == nil)
    }
}
