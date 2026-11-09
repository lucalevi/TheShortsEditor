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

    private func titled(_ url: URL, style: TitleStyle = .bold, entrance: TitleEntrance = .none, position: Double = TitlePlacement.top.verticalPosition) async throws -> Project {
        var project = try await project(with: url, framing: .fill)
        let id = project.addTitle(at: CMTime(value: 3, timescale: 10), text: "Watch this")
        project.updateTitle(id) { title in
            title.style = style
            title.entrance = entrance
            title.verticalPosition = position
            title.start = CMTime(value: 9, timescale: 30)
            title.duration = CMTime(value: 18, timescale: 30)
        }
        return project
    }

    /// Pixels of the title's own colours: white letters, or the white/yellow line boxes.
    private func titlePixels(_ image: CGImage, in rect: CGRect) -> Int {
        var count = 0
        for y in stride(from: Int(rect.minY), to: Int(rect.maxY), by: 4) {
            for x in stride(from: Int(rect.minX), to: Int(rect.maxX), by: 4) {
                let p = Fixture.pixel(image, x: x, y: y)
                if p.r > 200 && p.g > 180 && p.b < 60 || p.r > 200 && p.g > 200 && p.b > 200 || isBlack(p) { count += 1 }
            }
        }
        return count
    }

    @Test(arguments: TitleStyle.allCases)
    func titlesAreDrawnWhereThePreviewSays(style: TitleStyle) async throws {
        let url = try await Fixture.video(width: 180, height: 320, bgra: red)
        let project = try await titled(url, style: style)
        let box = try #require(TitlePreview.frame(of: project.titles[0]))
        #expect(abs(box.midY - CGFloat(TitlePlacement.top.verticalPosition) * 1920) < 2)
        let built = try await CompositionBuilder.build(project)
        let during = try await frame(of: built, at: 0.6)
        #expect(titlePixels(during, in: box) > 200)
        // Outside the title the picture is untouched.
        #expect(isRed(Fixture.pixel(during, x: 540, y: Int(box.maxY) + 60)))
        let before = try await frame(of: built, at: 0.1)
        #expect(titlePixels(before, in: box) == 0)
    }

    @Test func titleStaysOnTheCanvasWhenDraggedToTheEdge() async throws {
        let url = try await Fixture.video(width: 180, height: 320, bgra: red)
        let project = try await titled(url, position: 1)
        let box = try #require(TitlePreview.frame(of: project.titles[0]))
        #expect(box.maxY <= 1920 && box.minY > 1500)
        #expect(SafeZone.covers(box))
        let image = try await frame(of: CompositionBuilder.build(project), at: 0.6)
        #expect(titlePixels(image, in: box) > 200)
    }

    @Test func fadingTitleIsFainterAtFirst() async throws {
        let url = try await Fixture.video(width: 180, height: 320, bgra: red)
        let built = try await CompositionBuilder.build(try await titled(url, style: .label, entrance: .fade))
        let box = try #require(TitlePreview.frame(of: try await titled(url, style: .label).titles[0]))
        let early = try await frame(of: built, at: 0.3 + 1.0 / 30)
        let solid = try await frame(of: CompositionBuilder.build(try await titled(url, style: .label)), at: 0.3 + 1.0 / 30)
        #expect(titlePixels(solid, in: box) > 200)
        #expect(titlePixels(early, in: box) < titlePixels(solid, in: box) / 4)
        // Half way through the fade-in, the white box is a mix of white and the red video.
        let half = Fixture.pixel(try await frame(of: built, at: 0.3 + 0.15), x: Int(box.minX) + 4, y: Int(box.midY))
        #expect(half.r > 200 && half.g > 90 && half.g < 170)
    }

    @Test func poppingTitleStartsSmaller() async throws {
        let url = try await Fixture.video(width: 180, height: 320, bgra: red)
        let at = 0.3 + 1.0 / 30
        let popping = try await frame(of: CompositionBuilder.build(try await titled(url, style: .label, entrance: .pop)), at: at)
        let solid = try await frame(of: CompositionBuilder.build(try await titled(url, style: .label)), at: at)
        let box = try #require(TitlePreview.frame(of: try await titled(url, style: .label).titles[0]))
        #expect(titlePixels(popping, in: box) < titlePixels(solid, in: box) * 8 / 10)
        let settled = try await frame(of: CompositionBuilder.build(try await titled(url, style: .label, entrance: .pop)), at: 0.7)
        #expect(titlePixels(settled, in: box) == titlePixels(solid, in: box))
    }

    @Test func titleWithoutTextDrawsNothing() {
        #expect(TitleRenderer.image(text: "  \n ", style: .bold) == nil)
        #expect(TitlePreview.frame(of: TextOverlay(text: "", start: .zero, duration: .oneFrame)) == nil)
    }

    @Test func longTitlesWrapWithinTheMaximumWidth() throws {
        let one = try #require(TitleRenderer.image(text: "Hook", style: .label))
        let long = try #require(TitleRenderer.image(text: "This is a much longer hook that has to wrap onto more lines", style: .label))
        #expect(long.height > one.height * 2)
        let box = try #require(TitlePreview.frame(of: TextOverlay(text: "This is a much longer hook that has to wrap", start: .zero, duration: .oneFrame)))
        #expect(box.maxX <= Project.canvasSize.width - SafeZone.right)
    }
}
