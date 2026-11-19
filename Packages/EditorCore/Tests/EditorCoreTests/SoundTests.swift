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

struct SoundTests {
    @Test func voiceOversAreNumbered() {
        var (p, _) = talking()
        #expect(p.nextVoiceOverName == "Voice-over 1")
        _ = p.addAsset(sound("Voice-over 1.m4a"))
        p.assets[p.assets.count - 1].name = "Voice-over 1"
        _ = p.addAsset(sound("Voice-over 7.m4a"))
        p.assets[p.assets.count - 1].name = "Voice-over 7"
        _ = p.addAsset(sound("Voice-over notes.m4a"))
        p.assets[p.assets.count - 1].name = "Voice-over notes"
        #expect(p.nextVoiceOverName == "Voice-over 8")
    }

    @Test func aThrownAwayTakeLeavesMediaToo() throws {
        var (p, _) = talking()
        let assetID = p.addAsset(sound("take.m4a"))
        let firstAdded = p.addSound(of: assetID, at: seconds(1), isVoiceOver: true)
        let secondAdded = p.addSound(of: assetID, at: seconds(5), isVoiceOver: true)
        let first = try #require(firstAdded)
        let second = try #require(secondAdded)
        p.removeTake(first, assetID: assetID)
        // Still used by the second sound: the file stays.
        #expect(p.asset(id: assetID) != nil && p.sounds.count == 1)
        p.removeTake(second, assetID: assetID)
        #expect(p.asset(id: assetID) == nil && p.sounds.isEmpty)
    }

    @Test func aTakeWithNoVoiceIsNearlySilent() {
        #expect(AudioLevels(decibels: Array(repeating: -60, count: 300)).isNearlySilent)
        #expect(AudioLevels(decibels: []).isNearlySilent)
        // Mostly pauses, but some speech: not silent.
        #expect(!AudioLevels(decibels: Array(repeating: -60, count: 240) + Array(repeating: -22, count: 60)).isNearlySilent)
    }

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
