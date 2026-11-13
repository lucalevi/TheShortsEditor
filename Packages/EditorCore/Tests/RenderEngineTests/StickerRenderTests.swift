@preconcurrency import AVFoundation
import EditorCore
import Testing
@testable import RenderEngine

private let red: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 255, 255)

/// Stage H drawn: stickers, the new title looks, exits, following something, and text to speech.
@MainActor
struct StickerRenderTests {
    private func frame(of built: PlayableComposition, at seconds: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: built.composition)
        generator.videoComposition = built.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }

    private func t(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 600).snappedToFrame() }

    private func redShort(seconds: Int = 3) async throws -> Project {
        var project = Project()
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(try await Fixture.video(width: 180, height: 320, seconds: seconds, bgra: red))))
        return project
    }

    @Test func aSymbolStickerIsDrawnWhereItIs() async throws {
        var project = try await redShort()
        let id = project.addSticker(Sticker(.symbol("circle.fill"), color: .white, size: 300), at: .zero, x: 0.3, y: 0.6)
        project.updateTitle(id) { $0.entrance = .none }
        let image = try await frame(of: try await CompositionBuilder.build(project), at: 1)
        let centre = try #require(Fixture.whiteCentre(image))
        #expect(abs(centre.x - 0.3 * 1080) < 12 && abs(centre.y - 0.6 * 1920) < 12)
    }

    @Test func emojiAreDrawnInColour() throws {
        let image = try #require(StickerRenderer.image(Sticker(.emoji("🔥"), size: 200)))
        var colourful = 0
        for y in stride(from: 0, to: image.height, by: 4) {
            for x in stride(from: 0, to: image.width, by: 4) {
                let p = Fixture.pixel(image, x: x, y: y)
                if Int(p.r) - Int(p.b) > 80 { colourful += 1 }
            }
        }
        #expect(colourful > 50)
    }

    @Test func everyLookDrawsAndNeonGlows() throws {
        for style in TitleStyle.allCases {
            #expect(TitleRenderer.image(text: "Hook", look: style.look) != nil, "\(style)")
        }
        let neon = try #require(TitleRenderer.image(text: "Hi", look: TitleStyle.neon.look))
        // Pink light around the letters.
        var pink = 0
        for y in stride(from: 0, to: neon.height, by: 3) {
            for x in stride(from: 0, to: neon.width, by: 3) {
                let p = Fixture.pixel(neon, x: x, y: y)
                if p.r > 60, Int(p.r) - Int(p.g) > 40 { pink += 1 }
            }
        }
        #expect(pink > 30)
    }

    @Test func anExitFadesTheStickerAway() async throws {
        var project = try await redShort()
        let id = project.addSticker(Sticker(.symbol("circle.fill"), size: 400), at: .zero)
        project.updateTitle(id) { title in
            title.entrance = .none
            title.exit = ClipAnimation(.fade, duration: self.t(0.5))
        }
        let built = try await CompositionBuilder.build(project)
        let middle = Fixture.pixel(try await frame(of: built, at: 1), x: 540, y: 864)
        let end = Fixture.pixel(try await frame(of: built, at: 1.95), x: 540, y: 864)
        #expect(middle.g > 230)
        #expect(end.g < 80)
    }

    @Test func aTrackedStickerMovesWithItsPath() async throws {
        var project = try await redShort()
        let id = project.addSticker(Sticker(.symbol("circle.fill"), size: 200), at: .zero, x: 0.5, y: 0.5)
        project.updateTitle(id) { title in
            title.entrance = .none
            title.track = [TrackPoint(offset: .zero, x: 0.5, y: 0.5), TrackPoint(offset: self.t(1), x: 0.7, y: 0.4)]
        }
        let built = try await CompositionBuilder.build(project)
        let later = try #require(Fixture.whiteCentre(try await frame(of: built, at: 1.5)))
        #expect(abs(later.x - 0.7 * 1080) < 12 && abs(later.y - 0.4 * 1920) < 12)
    }

    @Test func theTrackerFollowsAMovingSquare() async throws {
        // The white square moves 1 px a frame to the right for a second (6 canvas px a frame once filled).
        let offsets = (0..<60).map { (min($0, 30), 0) }
        let url = try await Fixture.shakyVideo(width: 180, height: 320, seconds: 2, offsets: offsets)
        var project = Project()
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(url)))
        let path = try await SubjectTracker.track(project: project, at: (0.5, 0.5), during: CMTimeRange(start: .zero, duration: t(1.5)))
        let last = try #require(path.last)
        #expect(path.count > 10)
        // 30 source px × 6 = 180 canvas px = 0.167 of the width.
        #expect(abs(last.x - (0.5 + 180.0 / 1080)) < 0.03)
        #expect(abs(last.y - 0.5) < 0.03)
    }

    @Test func textToSpeechMakesASoundFile() async throws {
        guard let voice = SpeechMaker.voices(for: "en").first else { return }
        let folder = FileManager.default.temporaryDirectory.appending(path: "speech-\(UUID().uuidString)")
        let url = try await SpeechMaker.makeFile("Hello, and welcome to my Short.", voice: voice.id, in: folder)
        let media = try await MediaProbe.probe(url)
        #expect(media.hasAudio)
        #expect(media.duration.seconds > 0.8 && media.duration.seconds < 6)
    }
}
