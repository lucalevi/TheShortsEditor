@preconcurrency import AVFoundation
import EditorCore
import Testing
@testable import RenderEngine

private let red: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 255, 255)
private let blue: (UInt8, UInt8, UInt8, UInt8) = (255, 0, 0, 255)

@MainActor
struct CompositionBuilderTests {
    private func project(with url: URL, framing: Framing) async throws -> Project {
        var project = Project()
        let id = project.addAsset(try await MediaProbe.probe(url))
        project.appendClip(of: id)
        project.timeline.clips[0].framing = framing
        return project
    }

    private func frame(of built: PlayableComposition, at seconds: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: built.composition)
        generator.videoComposition = built.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }

    private func isRed(_ p: (r: UInt8, g: UInt8, b: UInt8)) -> Bool { p.r > 200 && p.g < 60 && p.b < 60 }
    private func isBlue(_ p: (r: UInt8, g: UInt8, b: UInt8)) -> Bool { p.b > 200 && p.r < 60 && p.g < 60 }
    private func isBlack(_ p: (r: UInt8, g: UInt8, b: UInt8)) -> Bool { p.r < 30 && p.g < 30 && p.b < 30 }

    @Test func probeReadsSizeAndDuration() async throws {
        let url = try await Fixture.video(width: 320, height: 180, bgra: red)
        let asset = try await MediaProbe.probe(url)
        #expect(asset.displaySize == CGSize(width: 320, height: 180))
        #expect(abs(asset.duration.seconds - 1) < 0.05)
        #expect(!asset.hasAudio)
    }

    @Test func rendersAtShortsResolution() async throws {
        let url = try await Fixture.video(width: 320, height: 180, bgra: red)
        let built = try await CompositionBuilder.build(try await project(with: url, framing: .fill))
        let image = try await frame(of: built, at: 0.5)
        #expect(image.width == 1080 && image.height == 1920)
    }

    @Test func fillCoversTheWholeCanvas() async throws {
        let url = try await Fixture.video(width: 320, height: 180, bgra: red)
        let image = try await frame(of: CompositionBuilder.build(try await project(with: url, framing: .fill)), at: 0.5)
        #expect(isRed(Fixture.pixel(image, x: 540, y: 50)))
        #expect(isRed(Fixture.pixel(image, x: 540, y: 960)))
    }

    @Test func fitLeavesBarsAboveAndBelow() async throws {
        let url = try await Fixture.video(width: 320, height: 180, bgra: red)
        let image = try await frame(of: CompositionBuilder.build(try await project(with: url, framing: .fit)), at: 0.5)
        #expect(isBlack(Fixture.pixel(image, x: 540, y: 50)))
        #expect(isRed(Fixture.pixel(image, x: 540, y: 960)))
    }

    @Test func splitClipsPlayBackToBack() async throws {
        let url = try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: red)
        var project = try await project(with: url, framing: .fill)
        project.timeline.split(at: CMTime(value: 1, timescale: 1))
        let built = try await CompositionBuilder.build(project)
        #expect(built.videoComposition.instructions.count == 2)
        #expect(abs(built.composition.duration.seconds - project.duration.seconds) < 0.01)
    }

    @Test func emptyTimelineIsAnError() async {
        await #expect(throws: CompositionBuilder.BuildError.self) {
            _ = try await CompositionBuilder.build(Project())
        }
    }

    @Test func pictureIsTheRightWayUp() async throws {
        let url = try await Fixture.video(width: 180, height: 320, bgra: red, bottomBGRA: blue)
        let image = try await frame(of: CompositionBuilder.build(try await project(with: url, framing: .fill)), at: 0.5)
        #expect(isRed(Fixture.pixel(image, x: 540, y: 300)))
        #expect(isBlue(Fixture.pixel(image, x: 540, y: 1600)))
    }

    @Test func phoneRotationIsApplied() async throws {
        // Stored landscape with a 90° turn, as an iPhone records portrait video. The stored top
        // (red) ends up on the right once the picture is turned upright.
        let turn = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 320, ty: 0)
        let url = try await Fixture.video(width: 320, height: 180, bgra: red, bottomBGRA: blue, transform: turn)
        let asset = try await MediaProbe.probe(url)
        #expect(asset.displaySize == CGSize(width: 180, height: 320))
        let image = try await frame(of: CompositionBuilder.build(try await project(with: url, framing: .fill)), at: 0.5)
        #expect(isRed(Fixture.pixel(image, x: 900, y: 960)))
        #expect(isBlue(Fixture.pixel(image, x: 180, y: 960)))
    }

    private func captioned(_ url: URL, visible: Bool = true, style: CaptionStyle = .bold) async throws -> Project {
        var project = try await project(with: url, framing: .fill)
        let assetID = project.assets[0].id
        project.transcripts[assetID] = Transcript(language: .english, words: [
            Word(text: "Hello", start: CMTime(value: 1, timescale: 10), duration: CMTime(value: 3, timescale: 10)),
            Word(text: "there", start: CMTime(value: 4, timescale: 10), duration: CMTime(value: 3, timescale: 10)),
        ])
        project.captions.isVisible = visible
        project.captions.style = style
        return project
    }

    /// The band where captions sit by default.
    private var captionBand: CGRect {
        let middle = CGFloat(CaptionSettings().verticalPosition) * 1920
        return CGRect(x: 150, y: middle - 150, width: 780, height: 300)
    }

    @Test(arguments: CaptionStyle.allCases)
    func captionsAreDrawnOnTheVideo(style: CaptionStyle) async throws {
        let url = try await Fixture.video(width: 180, height: 320, bgra: red)
        let built = try await CompositionBuilder.build(try await captioned(url, style: style))
        let during = try await frame(of: built, at: 0.5)
        #expect(Fixture.whitePixels(during, in: captionBand) > 500)
        // Away from the caption the picture is untouched.
        #expect(isRed(Fixture.pixel(during, x: 540, y: 300)))
    }

    @Test func noCaptionsBeforeTheFirstWordOrWhenHidden() async throws {
        let url = try await Fixture.video(width: 180, height: 320, bgra: red)
        let before = try await frame(of: CompositionBuilder.build(try await captioned(url)), at: 0.03)
        #expect(Fixture.whitePixels(before, in: captionBand) == 0)
        let hidden = try await frame(of: CompositionBuilder.build(try await captioned(url, visible: false)), at: 0.5)
        #expect(Fixture.whitePixels(hidden, in: captionBand) == 0)
    }

    @Test func captionStaysInsideTheSafeArea() {
        var settings = Project()
        settings.captions.verticalPosition = 1
        let track = CaptionTrack(project: settings)
        let top = track.top(forHeight: 200)
        #expect(top + 200 <= Project.canvasSize.height - SafeZone.bottom)
        settings.captions.verticalPosition = 0
        #expect(CaptionTrack(project: settings).top(forHeight: 200) >= SafeZone.top)
    }
}
