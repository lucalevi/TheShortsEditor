@preconcurrency import AVFoundation
import EditorCore
import Testing

@testable import RenderEngine

private let red: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 255, 255)
private let blue: (UInt8, UInt8, UInt8, UInt8) = (255, 0, 0, 255)

@MainActor
struct SpeedAndSoundRenderTests {
    private func frame(of built: PlayableComposition, at seconds: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: built.composition)
        generator.videoComposition = built.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }

    private func isRed(_ p: (r: UInt8, g: UInt8, b: UInt8)) -> Bool { p.r > 200 && p.g < 60 && p.b < 60 }
    private func isBlue(_ p: (r: UInt8, g: UInt8, b: UInt8)) -> Bool { p.b > 200 && p.r < 60 && p.g < 60 }

    private func oneClip(_ url: URL) async throws -> Project {
        var project = Project()
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(url)))
        return project
    }

    /// How many pixels of `image` are close to `color` (r, g, b).
    private func count(_ image: CGImage, near color: (Int, Int, Int)) -> Int {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 0, to: data.count, by: 4).count {
            data[$0 + 3] > 200 && abs(Int(data[$0]) - color.0) < 40 && abs(Int(data[$0 + 1]) - color.1) < 40 && abs(Int(data[$0 + 2]) - color.2) < 40
        }
    }

    // MARK: Speed

    @Test func aFastClipPlaysInHalfTheTimeWithItsSound() async throws {
        let url = try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: red, toneFrom: 0)
        var project = try await oneClip(url)
        project.setSpeed(2, for: project.timeline.clips[0].id)
        let built = try await CompositionBuilder.build(project)
        #expect(abs(built.composition.duration.seconds - 1) < 0.05)
        let audio = try #require(try await built.composition.loadTracks(withMediaType: .audio).first)
        #expect(abs(try await audio.load(.timeRange).duration.seconds - 1) < 0.05)
        #expect(built.makePlayerItem().audioTimePitchAlgorithm == .spectral)
    }

    /// 286 frames at 2× (9.533 s became 4.766666667 s of sound for 143/30 s of
    /// picture): the sound must end exactly with the picture, or the player shows nothing.
    @Test func aFastClipsSoundEndsExactlyWithItsPicture() async throws {
        let url = try await Fixture.video(width: 180, height: 320, seconds: 10, bgra: red, toneFrom: 0)
        var project = try await oneClip(url)
        project.timeline.clips[0].duration = CMTime(value: 286, timescale: 30)
        project.setSpeed(2, for: project.timeline.clips[0].id)
        let built = try await CompositionBuilder.build(project)
        let video = try #require(try await built.composition.loadTracks(withMediaType: .video).first)
        let audio = try #require(try await built.composition.loadTracks(withMediaType: .audio).first)
        let pictureEnd = try await video.load(.timeRange).end
        let soundEnd = try await audio.load(.timeRange).end
        #expect(soundEnd <= pictureEnd, "sound ends at \(soundEnd.value)/\(soundEnd.timescale), picture at \(pictureEnd.value)/\(pictureEnd.timescale)")
        #expect(abs((pictureEnd - soundEnd).seconds) < 0.02)
    }

    // MARK: Sounds

    @Test func builtInEffectsAreMadeOnce() async throws {
        for effect in SoundEffect.allCases {
            let url = try effect.fileURL()
            let asset = try await MediaProbe.probe(url)
            #expect(!asset.hasVideo && asset.hasAudio)
            #expect(abs(asset.duration.seconds - effect.seconds) < 0.05, "\(effect)")
        }
    }

    @Test func soundEffectsAndVoiceOversAreMixedIn() async throws {
        let url = try await Fixture.video(width: 180, height: 320, seconds: 3, bgra: red, toneFrom: 0)
        var project = try await oneClip(url)
        let pop = project.addAsset(try await MediaProbe.probe(try SoundEffect.pop.fileURL()))
        let whoosh = project.addAsset(try await MediaProbe.probe(try SoundEffect.whoosh.fileURL()))
        project.addSound(of: pop, at: CMTime(value: 1, timescale: 10))
        project.addSound(of: whoosh, at: CMTime(value: 1, timescale: 10))
        let built = try await CompositionBuilder.build(project)
        // The clip's own sound, plus two rows for the overlapping effects.
        #expect(try await built.composition.loadTracks(withMediaType: .audio).count == 3)
        #expect(built.audioMix.inputParameters.count == 3)
        #expect(abs(built.composition.duration.seconds - 3) < 0.05)
    }

    @Test(.timeLimit(.minutes(1)))
    func voiceCleanUpKeepsTheTiming() async throws {
        guard VoiceCleaner.isAvailable else { return }
        let url = try await Fixture.sound(seconds: 2)
        let cleaned = try await VoiceCleaner.clean(url)
        #expect(VoiceCleaner.existingCleanedURL(for: url) == cleaned)
        let original = try AVAudioFile(forReading: url), result = try AVAudioFile(forReading: cleaned)
        #expect(abs(Double(result.length) / result.fileFormat.sampleRate - Double(original.length) / original.fileFormat.sampleRate) < 0.02)
    }
}
