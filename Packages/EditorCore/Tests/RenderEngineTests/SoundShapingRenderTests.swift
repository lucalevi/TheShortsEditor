@preconcurrency import AVFoundation
import EditorCore
import Testing

@testable import RenderEngine

@MainActor
struct SoundShapingRenderTests {
    private let red: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 255, 255)

    private func seconds(_ from: Double, _ to: Double) -> CMTimeRange {
        CMTimeRange(start: CMTime(seconds: from, preferredTimescale: 600), end: CMTime(seconds: to, preferredTimescale: 600))
    }

    /// A Short of one clip with a loud tone all the way through.
    private func project(seconds: Int = 2) async throws -> Project {
        let url = try await Fixture.video(width: 180, height: 320, seconds: seconds, bgra: red, toneFrom: 0)
        var project = Project()
        let id = project.addAsset(try await MediaProbe.probe(url))
        project.appendClip(of: id)
        return project
    }

    /// The loudest sample of a sound file between two times (seconds), and its length.
    private func filePeak(_ url: URL, from: Double = 0, to: Double = .infinity) throws -> (peak: Float, seconds: Double) {
        let file = try AVAudioFile(forReading: url)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let rate = file.processingFormat.sampleRate
        let first = Int(from * rate), last = min(Int(buffer.frameLength), Int(min(to, 1e6) * rate))
        var peak: Float = 0
        for channel in 0..<Int(buffer.format.channelCount) where first < last {
            for i in first..<last { peak = max(peak, abs(buffer.floatChannelData![channel][i])) }
        }
        return (peak, Double(file.length) / rate)
    }

    @Test func fadeInStartsSilentAndReachesFullVolume() async throws {
        var p = try await project()
        let full = try #require(try await AudioProbe.peak(of: p, in: seconds(1.5, 1.9)))
        p.timeline.clips[0].fadeIn = CMTime(value: 1, timescale: 1)
        let start = try #require(try await AudioProbe.peak(of: p, in: seconds(0, 0.1)))
        let middle = try #require(try await AudioProbe.peak(of: p, in: seconds(0.45, 0.55)))
        let later = try #require(try await AudioProbe.peak(of: p, in: seconds(1.5, 1.9)))
        #expect(start < full * 0.15)
        #expect(abs(middle / full - 0.5) < 0.1)
        #expect(abs(later / full - 1) < 0.03)
    }

    @Test func pointsOnTheVolumeLineAreHeard() async throws {
        var p = try await project()
        let full = try #require(try await AudioProbe.peak(of: p, in: seconds(0, 0.5)))
        p.timeline.clips[0].addVolumeKey(atOffset: CMTime(value: 1, timescale: 1), level: 1)
        p.timeline.clips[0].addVolumeKey(atOffset: CMTime(value: 3, timescale: 2), level: 0.2)
        p.timeline.clips[0].addVolumeKey(atOffset: CMTime(value: 2, timescale: 1), level: 0.2)
        let before = try #require(try await AudioProbe.peak(of: p, in: seconds(0.2, 0.9)))
        let after = try #require(try await AudioProbe.peak(of: p, in: seconds(1.8, 1.95)))
        #expect(abs(before / full - 1) < 0.03)
        #expect(abs(after / full - 0.2) < 0.03, "\(after / full) \(p.timeline.clips[0].soundEnvelope())")
    }

    @Test func detachedSoundStillPlaysFromTheSoundRow() async throws {
        var p = try await project()
        let before = try #require(try await AudioProbe.peak(of: p, in: seconds(0.2, 1.8)))
        p.detachSound(of: p.timeline.clips[0].id)
        let built = try await CompositionBuilder.build(p)
        // The clips' own track is gone; the sound row has one.
        #expect(try await built.composition.loadTracks(withMediaType: .audio).count == 1)
        let after = try #require(try await AudioProbe.peak(of: p, in: seconds(0.2, 1.8)))
        #expect(abs(after / before - 1) < 0.03)
    }

    @Test func everyEffectKeepsTheLengthAndMakesSound() async throws {
        let source = try await Fixture.sound(seconds: 2, frequency: 440, amplitude: 0.3)
        let original = try filePeak(source)
        for effect in VoiceEffect.allCases {
            let url = try await SoundProcessor.process(source, recipe: .init(effect: effect, equalizer: nil))
            let result = try filePeak(url, from: 0.3, to: 1.7)
            #expect(abs(try filePeak(url).seconds - original.seconds) < 0.01, "\(effect)")
            #expect(result.peak > 0.02, "\(effect) is silent")
            #expect(result.peak < 1, "\(effect) clips")
        }
        for eq in SoundEQ.allCases {
            let url = try await SoundProcessor.process(source, recipe: .init(effect: nil, equalizer: eq))
            #expect(try filePeak(url, from: 0.3, to: 1.7).peak > 0.1, "\(eq)")
        }
    }

    @Test func telephoneAndLessBassTakeOutLowSound() async throws {
        let hum = try await Fixture.sound(seconds: 2, frequency: 80, amplitude: 0.3)
        let original = try filePeak(hum, from: 0.5, to: 1.5).peak
        for recipe in [SoundProcessor.Recipe(effect: .telephone, equalizer: nil), .init(effect: nil, equalizer: .lessBass)] {
            let url = try await SoundProcessor.process(hum, recipe: recipe)
            #expect(try filePeak(url, from: 0.5, to: 1.5).peak < original * 0.3, "\(recipe)")
        }
    }

    @Test func clipsPlayThroughTheirEffectOnceItIsMade() async throws {
        var p = try await project()
        let plain = try #require(try await AudioProbe.peak(of: p, in: seconds(0.3, 1.7)))
        p.timeline.clips[0].voiceEffect = .megaphone
        let media = try #require(p.asset(id: p.timeline.clips[0].assetID))
        // Not made yet: it plays as it was.
        #expect(
            SoundProcessor.playedURL(for: p.timeline.clips[0], media: media) == media.url
                || FileManager.default.fileExists(atPath: SoundProcessor.playedURL(for: p.timeline.clips[0], media: media).path))
        let made = try await SoundProcessor.process(SoundProcessor.baseURL(for: p.timeline.clips[0], media: media), recipe: .init(p.timeline.clips[0]))
        #expect(SoundProcessor.playedURL(for: p.timeline.clips[0], media: media) == made)
        let shaped = try #require(try await AudioProbe.peak(of: p, in: seconds(0.3, 1.7)))
        // The megaphone pushes the sound into overdrive: much louder peaks than the plain tone.
        #expect(shaped > plain * 1.3)
    }
}
