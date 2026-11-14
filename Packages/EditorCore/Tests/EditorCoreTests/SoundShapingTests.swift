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

private func near(_ a: Double, _ b: Double, _ tolerance: Double = 0.02) -> Bool { abs(a - b) < tolerance }

struct VolumeLineTests {
    @Test func fadesShapeTheSound() {
        var clip = Clip(assetID: UUID(), sourceStart: .zero, duration: t(4))
        clip.fadeIn = t(1)
        clip.fadeOut = t(2)
        #expect(clip.soundLevel(atOffset: .zero) == 0)
        #expect(near(clip.soundLevel(atOffset: t(0.5)), 0.5))
        #expect(near(clip.soundLevel(atOffset: t(1.5)), 1))
        #expect(near(clip.soundLevel(atOffset: t(3)), 0.5))
        #expect(near(clip.soundLevel(atOffset: t(4)), 0))
        let envelope = clip.soundEnvelope()
        #expect(envelope.first?.volume == 0 && envelope.last?.volume == 0)
        #expect(near(AudioMix.volume(at: t(2), in: envelope), 1))
    }

    @Test func fadesLongerThanTheClipShareIt() {
        var clip = Clip(assetID: UUID(), sourceStart: .zero, duration: t(2))
        clip.fadeIn = t(3)
        clip.fadeOut = t(1)
        let fades = clip.heardFades
        #expect(near(fades.in.seconds, 1.5) && near(fades.out.seconds, 0.5))
    }

    @Test func pointsOnTheLineRaiseAndLowerTheSound() {
        var clip = Clip(assetID: UUID(), sourceStart: t(2), duration: t(4))
        clip.volume = 0.5
        clip.addVolumeKey(atOffset: t(1), level: 1)
        clip.addVolumeKey(atOffset: t(3), level: 0)
        // The first point pinned the line at both ends too.
        #expect(clip.volumeKeys.count == 4)
        #expect(clip.volumeKeys[1].time == t(3)) // source time
        #expect(near(clip.soundLevel(atOffset: t(2)), 0.25)) // 0.5 × halfway between 1 and 0
        #expect(near(clip.soundLevel(atOffset: t(3)), 0))
        #expect(near(clip.soundLevel(atOffset: t(3.5)), 0.25)) // back up towards the pinned end
        // A point added where one is replaces it.
        clip.addVolumeKey(atOffset: t(1), level: 2)
        #expect(clip.volumeKeys.count == 4 && clip.volumeKeys[1].level == 2)
    }

    @Test func aNewPointTakesTheLevelOfTheLine() {
        var clip = Clip(assetID: UUID(), sourceStart: .zero, duration: t(4))
        clip.addVolumeKey(atOffset: t(0), level: 0)
        clip.addVolumeKey(atOffset: t(4), level: 2)
        clip.addVolumeKey(atOffset: t(2))
        #expect(clip.volumeKeys.count == 3 && near(clip.volumeKeys[1].level, 1))
        // One point alone dips the line there and leaves its ends where they were.
        var single = Clip(assetID: UUID(), sourceStart: .zero, duration: t(4))
        let id = single.addVolumeKey(atOffset: t(2))
        single.volumeKeys[single.volumeKeys.firstIndex { $0.id == id }!].level = 0
        #expect(near(single.soundLevel(atOffset: .zero), 1) && near(single.soundLevel(atOffset: t(2)), 0))
    }

    @Test func splittingKeepsPointsAndPutsFadesAtTheOuterEnds() {
        var p = Project()
        let a = p.addAsset(video("a.mov"))
        p.appendClip(of: a)
        p.updateAnyClip(p.timeline.clips[0].id) { clip in
            clip.fadeIn = t(1)
            clip.fadeOut = t(1)
            clip.addVolumeKey(atOffset: t(7), level: 0.3)
        }
        p.timeline.split(at: t(5))
        let first = p.timeline.clips[0], second = p.timeline.clips[1]
        #expect(first.fadeIn == t(1) && first.fadeOut == .zero)
        #expect(second.fadeIn == .zero && second.fadeOut == t(1))
        #expect(first.visibleVolumeKeys.count == 1 && second.visibleVolumeKeys.count == 2) // start / the point and the end
        #expect(second.visibleVolumeKeys[0].offset == t(2))
    }

    @Test func removingPausesKeepsFadesAtTheOuterEnds() {
        var p = Project()
        let a = p.addAsset(video("a.mov"))
        p.appendClip(of: a)
        let id = p.timeline.clips[0].id
        p.updateAnyClip(id) {
            $0.fadeIn = t(1); $0.fadeOut = t(1)
        }
        p.apply(SilencePlan(sourceCuts: [id: [CMTimeRange(start: t(3), duration: t(2))]]))
        #expect(p.timeline.clips.count == 2)
        #expect(p.timeline.clips[0].fadeIn == t(1) && p.timeline.clips[0].fadeOut == .zero)
        #expect(p.timeline.clips[1].fadeIn == .zero && p.timeline.clips[1].fadeOut == t(1))
    }

    @Test func storylineFadesBetweenPartsOfOneRecording() {
        let asset = UUID()
        let first = Clip(assetID: asset, sourceStart: .zero, duration: t(2), volume: 1)
        let second = Clip(assetID: asset, sourceStart: t(2), duration: t(2), volume: 0.2)
        let envelope = AudioMix.storylineEnvelope([first, second])
        #expect(near(AudioMix.volume(at: t(2), in: envelope), 1))
        #expect(near(AudioMix.volume(at: t(2.1), in: envelope), 0.6))
        #expect(near(AudioMix.volume(at: t(2.2), in: envelope), 0.2))
        // Different recordings simply cut.
        let other = Clip(assetID: UUID(), sourceStart: t(2), duration: t(2), volume: 0.2)
        let cut = AudioMix.storylineEnvelope([first, other])
        #expect(near(AudioMix.volume(at: t(2.1), in: cut), 0.2))
    }

    @Test func tooLoudWhereVolumePushesTheSoundUp() {
        let levels = AudioLevels(decibels: Array(repeating: -12, count: 30) + Array(repeating: -3, count: 30))
        var clip = Clip(assetID: UUID(), sourceStart: .zero, duration: t(2))
        let ranges = AudioMix.tooLoudRanges(of: clip, levels: levels)
        #expect(ranges.count == 1 && near(ranges[0].start.seconds, 1, 0.04) && near(ranges[0].end.seconds, 2, 0.04))
        clip.volume = 2 // +6 dB: all of it
        #expect(AudioMix.tooLoudRanges(of: clip, levels: levels).first.map { near($0.duration.seconds, 2, 0.04) } == true)
        clip.volume = 0.25
        #expect(AudioMix.tooLoudRanges(of: clip, levels: levels).isEmpty)
    }
}

struct DetachSoundTests {
    private func project() -> (Project, Clip.ID) {
        var p = Project()
        let a = p.addAsset(video("a.mov"))
        let b = p.addAsset(video("b.mov"))
        p.appendClip(of: a)
        p.appendClip(of: b)
        return (p, p.timeline.clips[1].id)
    }

    @Test func detachMovesTheSoundToTheSoundRow() throws {
        var (p, id) = project()
        p.updateAnyClip(id) {
            $0.volume = 0.7; $0.fadeIn = t(1)
        }
        let detached = p.detachSound(of: id)
        let soundID = try #require(detached)
        let sound = try #require(p.sound(id: soundID))
        #expect(sound.detachedFrom == id && sound.start == t(10) && sound.duration == t(10))
        #expect(sound.clip.volume == 0.7 && sound.clip.fadeIn == t(1) && sound.clip.effectiveVolume == 0.7)
        let clip = try #require(p.anyClip(id: id))
        #expect(clip.soundDetached && clip.effectiveVolume == 0)
        let again = p.detachSound(of: id)
        #expect(again == nil) // only once
    }

    @Test func detachedSoundCanStartBeforeThePicture() throws {
        var (p, id) = project()
        let detached = p.detachSound(of: id)
        let soundID = try #require(detached)
        // The second file has sound before the part used: trim its start a second earlier (a J-cut).
        p.updateAnyClip(id) {
            $0.sourceStart = t(2); $0.duration = t(8)
        }
        p.updateSound(soundID) {
            $0.clip.sourceStart = t(2); $0.clip.duration = t(8)
        }
        let trimmed = p.trimSound(soundID, edge: .start, by: t(-1))
        #expect(trimmed)
        let sound = try #require(p.sound(id: soundID))
        #expect(sound.start == t(9) && sound.clip.sourceStart == t(1) && sound.duration == t(9))
    }

    @Test func reattachRemovesTheDetachedSound() throws {
        var (p, id) = project()
        p.detachSound(of: id)
        p.reattachSound(of: id)
        #expect(p.sounds.isEmpty && p.anyClip(id: id)?.soundDetached == false)
    }

    @Test func detachedSoundStillLowersTheMusic() throws {
        var (p, id) = project()
        let levels = AudioLevels(decibels: Array(repeating: -20, count: 300))
        let before = AudioMix.speechRanges(in: p, levels: [p.timeline.clips[1].assetID: levels])
        p.detachSound(of: id)
        let after = AudioMix.speechRanges(in: p, levels: [p.timeline.clips[1].assetID: levels])
        #expect(before == after && !after.isEmpty)
    }

    @Test func soundSettingsAreCopiedAndReset() throws {
        var (p, id) = project()
        let first = p.timeline.clips[0].id
        p.updateAnyClip(first) { clip in
            clip.fadeOut = t(2)
            clip.voiceEffect = .robot
            clip.equalizer = .voice
            clip.addVolumeKey(atOffset: t(1), level: 0.5)
        }
        p.pasteSettings([.sound], from: try #require(p.anyClip(id: first)), to: id)
        let pasted = try #require(p.anyClip(id: id))
        #expect(pasted.fadeOut == t(2) && pasted.voiceEffect == .robot && pasted.equalizer == .voice)
        #expect(pasted.visibleVolumeKeys.map(\.offset) == [.zero, t(1), t(10)])
        #expect(p.changedSettings(of: id).contains(.sound))
        p.resetSettings([.sound], of: id)
        #expect(p.anyClip(id: id)?.hasSoundShaping == false)
    }

    @Test func newSoundSettingsAreSavedAndOldFilesStillOpen() throws {
        var (p, id) = project()
        p.updateAnyClip(id) { clip in
            clip.fadeIn = t(0.5)
            clip.voiceEffect = .echo
            clip.addVolumeKey(atOffset: t(2), level: 1.5)
        }
        p.detachSound(of: id)
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(Project.self, from: data)
        #expect(back == p)
        // A clip saved before this stage has none of the new keys.
        let old =
            #"{"id":"\#(UUID())","assetID":"\#(UUID())","sourceStart":{"value":0,"timescale":600},"duration":{"value":600,"timescale":600},"framing":"fill"}"#
        let clip = try JSONDecoder().decode(Clip.self, from: Data(old.utf8))
        #expect(!clip.hasSoundShaping && !clip.soundDetached)
    }
}
