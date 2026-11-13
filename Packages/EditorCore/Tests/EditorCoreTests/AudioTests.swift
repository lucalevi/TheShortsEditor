import CoreGraphics
import CoreMedia
import Foundation
import Testing
@testable import EditorCore

private func t(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 600) }

/// A 10 s clip of a talking file, plus a 30 s song.
private func project(clipSeconds: Int64 = 10, songSeconds: Int64 = 30) -> Project {
    var project = Project()
    let video = MediaAsset(url: URL(fileURLWithPath: "/tmp/talk.mov"), name: "talk", duration: CMTime(value: clipSeconds, timescale: 1),
                           displaySize: CGSize(width: 1080, height: 1920), hasAudio: true)
    let song = MediaAsset(url: URL(fileURLWithPath: "/tmp/song.m4a"), name: "song", duration: CMTime(value: songSeconds, timescale: 1),
                          displaySize: .zero, hasAudio: true, hasVideo: false)
    project.addAsset(video)
    project.addAsset(song)
    project.appendClip(of: video.id)
    return project
}

/// Loud (−20 dB) during `talking` seconds of the file, background noise (−60 dB) elsewhere.
private func levels(seconds: Int, talking: [ClosedRange<Double>]) -> AudioLevels {
    AudioLevels(decibels: (0..<(seconds * 30)).map { frame in
        let time = Double(frame) / 30
        return talking.contains { $0.contains(time) } ? -20 : -60
    })
}

struct ClipSoundTests {
    @Test func splitAndPauseRemovalKeepTheSound() {
        var p = project()
        p.timeline.clips[0].volume = 1.5
        p.timeline.clips[0].isMuted = true
        p.timeline.split(at: t(4))
        #expect(p.timeline.clips.allSatisfy { $0.volume == 1.5 && $0.isMuted })
        p.apply(SilencePlan(sourceCuts: [p.timeline.clips[0].id: [CMTimeRange(start: t(1), end: t(2))]], timelineCuts: []))
        #expect(p.timeline.clips.count == 3)
        #expect(p.timeline.clips.allSatisfy { $0.volume == 1.5 && $0.isMuted })
    }

    @Test func mutedClipPlaysAtZero() {
        var clip = Clip(assetID: UUID(), sourceStart: .zero, duration: t(1), volume: 0.8)
        #expect(clip.effectiveVolume == 0.8)
        clip.isMuted = true
        #expect(clip.effectiveVolume == 0)
    }

    @Test func soundFilesNeverBecomeClips() {
        var p = project()
        let song = p.assets[1].id
        #expect(p.appendClip(of: song) == nil)
        #expect(p.timeline.clips.count == 1)
    }

    @Test func oldProjectsWithoutSoundSettingsStillLoad() throws {
        let json = #"{"id":"\#(UUID())","assetID":"\#(UUID())","sourceStart":{"value":0,"timescale":1},"duration":{"value":1,"timescale":1},"framing":"fill"}"#
        let clip = try JSONDecoder().decode(Clip.self, from: Data(json.utf8))
        #expect(clip.volume == 1 && !clip.isMuted)
    }
}

struct MusicTests {
    @Test func playsForTheShortOrUntilTheSongEnds() {
        var p = project(clipSeconds: 10, songSeconds: 30)
        #expect(p.musicRange == nil)
        p.setMusic(p.assets[1].id)
        #expect(p.musicRange == CMTimeRange(start: .zero, duration: t(10)))
        #expect(!p.musicEndsEarly)
        p.setMusicStart(t(25))
        #expect(p.musicRange?.duration == t(5))
        #expect(p.musicEndsEarly)
    }

    @Test func songStartLeavesASecondAndSnaps() {
        var p = project()
        p.setMusic(p.assets[1].id)
        p.setMusicStart(t(100))
        #expect(p.music?.sourceStart == t(29))
        p.setMusicStart(t(1.01))
        #expect(p.music?.sourceStart == CMTime(value: 30, timescale: 30))
    }

    @Test func choosingTheSameSongKeepsItsSettings() {
        var p = project()
        p.setMusic(p.assets[1].id)
        p.music?.volume = 0.2
        p.setMusic(p.assets[1].id)
        #expect(p.music?.volume == 0.2)
    }

    @Test func speechIsFoundFromLoudnessAndBridgesShortGaps() {
        let p = project()
        let audio = levels(seconds: 10, talking: [1...3, 3.3...4, 7...8])
        let speech = AudioMix.speechRanges(in: p, levels: [p.assets[0].id: audio])
        #expect(speech.count == 2)
        #expect(abs(speech[0].start.seconds - 1) < 0.05 && abs(speech[0].end.seconds - 4) < 0.05)
        #expect(abs(speech[1].start.seconds - 7) < 0.05)
    }

    @Test func speechFollowsTheClipsOnTheTimeline() {
        var p = project()
        p.timeline.split(at: t(5))
        p.timeline.remove(p.timeline.clips[0].id)  // the 5…10 s part now starts at 0
        let speech = AudioMix.speechRanges(in: p, levels: [p.assets[0].id: levels(seconds: 10, talking: [7...8])])
        #expect(speech.count == 1)
        #expect(abs(speech[0].start.seconds - 2) < 0.05)
    }

    @Test func mutedClipsAndQuietFilesHaveNoSpeech() {
        var p = project()
        let quiet = AudioLevels(decibels: (0..<300).map { $0 % 60 < 30 ? -58 : -62 })
        #expect(AudioMix.speechRanges(in: p, levels: [p.assets[0].id: quiet]).isEmpty)
        p.timeline.clips[0].isMuted = true
        #expect(AudioMix.speechRanges(in: p, levels: [p.assets[0].id: levels(seconds: 10, talking: [1...3])]).isEmpty)
    }

    @Test func songFadesAndGoesDownUnderSpeech() {
        var p = project()
        p.setMusic(p.assets[1].id)
        let speech = [CMTimeRange(start: t(4), end: t(6))]
        let curve = AudioMix.musicEnvelope(for: p, speech: speech)
        let v = BackgroundMusic.defaultVolume
        func at(_ s: Double) -> Double { AudioMix.volume(at: t(s), in: curve) }
        #expect(at(0) == 0)                                     // fading in
        #expect(abs(at(0.5) - v / 2) < 0.01)
        #expect(abs(at(2) - v) < 0.001)                         // full between
        #expect(abs(at(5) - v * BackgroundMusic.loweredFraction) < 0.001) // under speech
        #expect(abs(at(3.9) - v * (1 - (1 - BackgroundMusic.loweredFraction) * 0.6)) < 0.001) // going down before speech
        #expect(abs(at(7) - v) < 0.001)                         // back up
        #expect(abs(at(9) - v / 2) < 0.01)                      // fading out
        #expect(at(10) == 0)
    }

    @Test func withoutLoweringOrFadesTheSongIsFlat() {
        var p = project()
        p.setMusic(p.assets[1].id)
        p.music?.lowersUnderSpeech = false
        p.music?.fadesIn = false
        p.music?.fadesOut = false
        let curve = AudioMix.musicEnvelope(for: p, speech: [CMTimeRange(start: t(4), end: t(6))])
        #expect(curve.count == 2)
        #expect(curve.allSatisfy { $0.volume == BackgroundMusic.defaultVolume })
    }

    @Test func aSongAddedAsASoundGoesDownUnderSpeech() {
        var p = project()
        let id = p.addSound(of: p.assets[1].id, at: t(2))!
        #expect(p.sound(id: id)?.lowersUnderSpeech == true)    // a 30 s file is a song
        let sound = p.sound(id: id)!
        let curve = AudioMix.lowered(sound.clip.soundEnvelope(), startingAt: sound.start, speech: [CMTimeRange(start: t(4), end: t(6))])
        func at(_ s: Double) -> Double { AudioMix.volume(at: t(s) - sound.start, in: curve) }
        #expect(abs(at(3) - 1) < 0.001)                              // its own level before
        #expect(abs(at(5) - BackgroundMusic.loweredFraction) < 0.001) // under speech
        #expect(abs(at(3.9) - (1 - (1 - BackgroundMusic.loweredFraction) * 0.6)) < 0.001)
        #expect(abs(at(7) - 1) < 0.001)                              // back up
        #expect(curve.first?.time == .zero && curve.last?.time == sound.duration)
    }

    @Test func shortSoundsAndVoiceOversAreNotLowered() throws {
        var p = project(songSeconds: 3)
        let effect = p.addSound(of: p.assets[1].id, at: t(1))!
        let voice = p.addSound(of: p.assets[1].id, at: t(5), isVoiceOver: true)!
        #expect(p.sound(id: effect)?.lowersUnderSpeech == false)
        #expect(p.sound(id: voice)?.lowersUnderSpeech == false)
        #expect(p.sound(id: voice)?.canLowerUnderSpeech == false)
        // Saved only when on, and kept through a split.
        p.updateSound(effect) { $0.lowersUnderSpeech = true }
        #expect(try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(p)) == p)
        p.splitSound(effect, at: t(2))
        let effects = p.sounds.filter { !$0.isVoiceOver }
        #expect(effects.count == 2)
        #expect(effects.allSatisfy { $0.lowersUnderSpeech })
    }

    @Test func noSpeechLeavesASoundAsItIs() {
        var p = project()
        let id = p.addSound(of: p.assets[1].id, at: .zero)!
        let envelope = p.sound(id: id)!.clip.soundEnvelope()
        #expect(AudioMix.lowered(envelope, startingAt: .zero, speech: []) == envelope)
    }

    @Test func musicSurvivesSavingAndLoading() throws {
        var p = project()
        p.setMusic(p.assets[1].id)
        p.setMusicStart(t(3))
        p.music?.fadesOut = false
        #expect(try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(p)) == p)
    }

    @Test func longShortWithMusicGetsAContentIDWarning() {
        var p = project(clipSeconds: 70, songSeconds: 200)
        #expect(!ExportReview.issues(for: p, openingPeak: 0.5).map(\.kind).contains(.musicOverOneMinute))
        p.setMusic(p.assets[1].id)
        #expect(ExportReview.issues(for: p, openingPeak: 0.5).first?.kind == .musicOverOneMinute)
        var short = project(clipSeconds: 50)
        short.setMusic(short.assets[1].id)
        #expect(!ExportReview.issues(for: short, openingPeak: 0.5).map(\.kind).contains(.musicOverOneMinute))
    }
}

struct LoudnessTests {
    private func sine(frequency: Double, dBFS: Double, seconds: Double, stereo: Bool = true) -> [Float] {
        let amplitude = pow(10, dBFS / 20)
        let count = Int(seconds * 48_000)
        var samples = [Float](repeating: 0, count: count * 2)
        for i in 0..<count {
            let x = Float(amplitude * sin(2 * .pi * frequency * Double(i) / 48_000))
            samples[2 * i] = x
            samples[2 * i + 1] = stereo ? x : 0
        }
        return samples
    }

    /// EBU Tech 3341, test 1: a stereo 1 kHz sine at −23 dBFS measures −23 LUFS.
    @Test func ebuReferenceTone() throws {
        var meter = LoudnessMeter()
        meter.add(interleaved: sine(frequency: 1000, dBFS: -23, seconds: 20))
        let loudness = try #require(meter.integratedLoudness)
        #expect(abs(loudness - -23) < 0.1)
    }

    /// EBU Tech 3341, test 3: −36, −23, −36 dBFS for 10 s each: the quiet parts are gated out.
    @Test func quietPartsAreLeftOut() throws {
        var meter = LoudnessMeter()
        meter.add(interleaved: sine(frequency: 1000, dBFS: -36, seconds: 10))
        meter.add(interleaved: sine(frequency: 1000, dBFS: -23, seconds: 60))
        meter.add(interleaved: sine(frequency: 1000, dBFS: -36, seconds: 10))
        let loudness = try #require(meter.integratedLoudness)
        #expect(abs(loudness - -23) < 0.1)
    }

    @Test func silenceHasNoLoudnessAndNoGain() {
        var meter = LoudnessMeter()
        meter.add(interleaved: [Float](repeating: 0, count: 96_000))
        #expect(meter.integratedLoudness == nil)
        #expect(meter.normalizingGain() == 1)
    }

    @Test func quietSoundIsBroughtUpToYouTubesLevel() {
        var meter = LoudnessMeter()
        meter.add(interleaved: sine(frequency: 1000, dBFS: -26, seconds: 5))
        // −26 LUFS → −14 LUFS is +12 dB; the peak (−26 dBFS) stays well under −1.
        #expect(abs(20 * log10(meter.normalizingGain()) - 12) < 0.15)
    }

    @Test func peaksStopTheBoost() {
        var meter = LoudnessMeter()
        var samples = sine(frequency: 1000, dBFS: -30, seconds: 5)
        samples[1000] = 0.5  // one click at −6 dBFS
        meter.add(interleaved: samples)
        #expect(abs(20 * log10(meter.normalizingGain()) - 5) < 0.05)
    }

    @Test func loudSoundIsTurnedDown() {
        var meter = LoudnessMeter()
        meter.add(interleaved: sine(frequency: 1000, dBFS: -6, seconds: 5))
        // About −6 LUFS → −14 LUFS: down 8 dB.
        #expect(abs(20 * log10(meter.normalizingGain()) - -8) < 0.15)
    }
}
