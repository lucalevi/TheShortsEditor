@preconcurrency import AVFoundation
import EditorCore
import Testing
@testable import RenderEngine

@MainActor
struct AudioMixTests {
    private let red: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 255, 255)
    private let full = CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 1))

    /// A Short of one clip; with `toneFrom`, the clip has a loud tone from that second on.
    private func project(seconds: Int = 1, toneFrom: Double? = 0) async throws -> Project {
        let url = try await Fixture.video(width: 180, height: 320, seconds: seconds, bgra: red, toneFrom: toneFrom)
        var project = Project()
        let id = project.addAsset(try await MediaProbe.probe(url))
        project.appendClip(of: id)
        return project
    }

    private func addSong(_ project: inout Project, seconds: Int = 10, amplitude: Double = 0.3) async throws {
        let song = try await MediaProbe.probe(try await Fixture.sound(seconds: seconds, amplitude: amplitude))
        project.setMusic(project.addAsset(song))
        project.music?.fadesIn = false
        project.music?.fadesOut = false
    }

    @Test func soundFilesAreReadAsMusic() async throws {
        let asset = try await MediaProbe.probe(try await Fixture.sound(seconds: 2))
        #expect(!asset.hasVideo && asset.hasAudio)
        #expect(abs(asset.duration.seconds - 2) < 0.1)
    }

    @Test func clipVolumeAndMuteChangeTheSound() async throws {
        var p = try await project()
        let normal = try #require(try await AudioProbe.peak(of: p, in: full))
        p.timeline.clips[0].volume = 0.5
        let half = try #require(try await AudioProbe.peak(of: p, in: full))
        #expect(abs(half / normal - 0.5) < 0.02)
        p.timeline.clips[0].volume = 1.5
        let louder = try #require(try await AudioProbe.peak(of: p, in: full))
        #expect(abs(louder / normal - 1.5) < 0.03)
        p.timeline.clips[0].isMuted = true
        #expect(try await AudioProbe.peak(of: p, in: full) == 0)
    }

    @Test func musicPlaysUnderASilentVideoAtItsVolume() async throws {
        var p = try await project(toneFrom: nil)
        #expect(try await AudioProbe.peak(of: p, in: full) == nil)
        try await addSong(&p, amplitude: 0.4)
        p.music?.volume = 0.5
        let peak = try #require(try await AudioProbe.peak(of: p, in: full))
        #expect(abs(peak - 0.2) < 0.03)
        // The song stops with the Short.
        let built = try await CompositionBuilder.build(p)
        #expect(abs(built.composition.duration.seconds - 1) < 0.05)
    }

    @Test func musicGoesDownWhereTheClipHasSpeech() async throws {
        var p = try await project(seconds: 4, toneFrom: 2)
        try await addSong(&p)
        let envelope = try await CompositionBuilder.build(p).musicEnvelope
        let v = BackgroundMusic.defaultVolume
        #expect(abs(AudioMix.volume(at: CMTime(value: 1, timescale: 1), in: envelope) - v) < 0.001)
        #expect(abs(AudioMix.volume(at: CMTime(value: 3, timescale: 1), in: envelope) - v * BackgroundMusic.loweredFraction) < 0.001)
        // And the mix really is quieter there: music alone before the speech, lowered after.
        p.timeline.clips[0].isMuted = false
        let before = try #require(try await AudioProbe.peak(of: p, in: CMTimeRange(start: CMTime(value: 1, timescale: 2), duration: CMTime(value: 1, timescale: 2))))
        #expect(abs(before - Float(0.3 * v)) < 0.03)
        p.music?.lowersUnderSpeech = false
        let flat = try await CompositionBuilder.build(p).musicEnvelope
        #expect(flat.allSatisfy { $0.volume == v })
    }

    private func loudness(of url: URL) async throws -> Double? {
        var p = Project()
        let id = p.addAsset(try await MediaProbe.probe(url))
        p.appendClip(of: id)
        return try await AudioProbe.loudness(of: p)?.integratedLoudness
    }

    @Test func exportBringsTheSoundToYouTubesLevel() async throws {
        let p = try await project(seconds: 3)
        let before = try #require(try await AudioProbe.loudness(of: p)?.integratedLoudness)
        #expect(before > -10)  // the fixture tone is loud
        let url = FileManager.default.temporaryDirectory.appending(path: "loud-\(UUID().uuidString).mp4")
        try await Exporter.export(p, to: url)
        let after = try #require(try await loudness(of: url))
        #expect(abs(after - LoudnessMeter.youTubeTarget) < 0.5)

        let untouched = FileManager.default.temporaryDirectory.appending(path: "raw-\(UUID().uuidString).mp4")
        try await Exporter.export(p, to: untouched, evenOutLoudness: false)
        #expect(abs(try #require(try await loudness(of: untouched)) - before) < 0.5)
    }
}
