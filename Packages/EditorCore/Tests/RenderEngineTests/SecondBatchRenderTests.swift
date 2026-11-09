@preconcurrency import AVFoundation
import EditorCore
import Testing
@testable import RenderEngine

private let red: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 255, 255)
private let blue: (UInt8, UInt8, UInt8, UInt8) = (255, 0, 0, 255)

@MainActor
struct SecondBatchRenderTests {
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
        let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
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

    // MARK: Text

    @Test func aTitleIsDrawnInItsOwnLook() async throws {
        let url = try await Fixture.video(width: 180, height: 320, bgra: blue)
        var project = try await oneClip(url)
        let id = project.addTitle(at: .zero, text: "Look at this")
        project.updateTitle(id) { title in
            title.entrance = .none
            title.look.boxColor = RGBA(1, 0, 0)
            title.look.boxPerLine = false
            title.look.textColor = .white
            title.horizontalPosition = 0.2
        }
        let box = try #require(TitlePreview.frame(of: project.titles[0]))
        #expect(box.minX < 20)   // pushed to the left edge, but kept on the canvas
        let image = try await frame(of: CompositionBuilder.build(project), at: 0.5)
        #expect(isRed(Fixture.pixel(image, x: Int(box.minX) + 6, y: Int(box.midY))))
    }

    @Test func typingShowsMoreLettersOverTime() async throws {
        var look = TitleStyle.bold.look
        look.outlineColor = nil
        let few = try #require(TitleRenderer.image(text: "Typing here", look: look, visibleCharacters: 2))
        let all = try #require(TitleRenderer.image(text: "Typing here", look: look))
        #expect(few.width == all.width)
        #expect(count(few, near: (255, 255, 255)) * 3 < count(all, near: (255, 255, 255)))
    }

    @Test func keyWordsAreInTheAccentColourAndEmojiGoAbove() throws {
        var settings = CaptionSettings()
        settings.style = .minimal
        settings.accentColor = RGBA(1, 0, 0)
        let plain = try #require(CaptionRenderer.image(words: ["make", "money"], keywords: [], currentWord: nil, emoji: nil, settings: settings))
        let keyword = try #require(CaptionRenderer.image(words: ["make", "money"], keywords: [1], currentWord: nil, emoji: nil, settings: settings))
        #expect(count(plain, near: (255, 0, 0)) < 20)
        #expect(count(keyword, near: (255, 0, 0)) > 200)
        let withEmoji = try #require(CaptionRenderer.image(words: ["make", "money"], keywords: [], currentWord: nil, emoji: "💰", settings: settings))
        #expect(withEmoji.height > plain.height)
        settings.sizeScale = 1.5
        let bigger = try #require(CaptionRenderer.image(words: ["make", "money"], keywords: [], currentWord: nil, emoji: nil, settings: settings))
        #expect(bigger.height > plain.height)
    }

    // MARK: Layouts

    @Test func splitScreenShowsBothClips() async throws {
        let main = try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: red)
        let other = try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: blue)
        var project = try await oneClip(main)
        let added = project.addOverlay(of: project.addAsset(try await MediaProbe.probe(other)), at: .zero)
        let id = try #require(added)
        project.updateOverlay(id) { $0.layout = .top }
        let image = try await frame(of: CompositionBuilder.build(project), at: 0.5)
        #expect(isBlue(Fixture.pixel(image, x: 540, y: 400)))
        #expect(isRed(Fixture.pixel(image, x: 540, y: 1500)))
    }

    // MARK: Reframing

    @Test func theSubjectIsFoundOnTheLeft() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "subject-\(UUID().uuidString).png")
        let width = 640, height = 360
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 1, green: 0.9, blue: 0.2, alpha: 1))
        context.fillEllipse(in: CGRect(x: 80, y: 120, width: 120, height: 120))
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        #expect(CGImageDestinationFinalize(destination))
        let media = try await MediaProbe.probe(url)
        let clip = Clip(assetID: media.id, sourceStart: .zero, duration: CMTime(value: 3, timescale: 1))
        let samples = try await Reframer.samples(for: clip, media: media)
        #expect(samples.count == 1)
        #expect(samples[0].x < 0.4)
    }
}
