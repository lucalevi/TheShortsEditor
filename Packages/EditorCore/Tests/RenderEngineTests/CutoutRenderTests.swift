@preconcurrency import AVFoundation
import CoreImage
import EditorCore
import Testing
@testable import RenderEngine

private let red: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 255, 255)
private let blue: (UInt8, UInt8, UInt8, UInt8) = (255, 0, 0, 255)
private let white: (UInt8, UInt8, UInt8, UInt8) = (255, 255, 255, 255)
private let black: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 255)
/// A green screen as a camera sees it (B, G, R).
private let screen: (UInt8, UInt8, UInt8, UInt8) = (77, 191, 51, 255)

/// Stage K drawn: green screen, masks, blend modes, the canvas colour and see-through copies.
@MainActor
struct CutoutRenderTests {
    private func frame(of built: PlayableComposition, at seconds: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: built.composition)
        generator.videoComposition = built.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }

    private func isRed(_ p: (r: UInt8, g: UInt8, b: UInt8)) -> Bool { p.r > 200 && p.g < 60 && p.b < 60 }
    private func isBlue(_ p: (r: UInt8, g: UInt8, b: UInt8)) -> Bool { p.b > 200 && p.r < 60 && p.g < 60 }

    /// A blue main clip with `overlay` (a portrait video, filling the canvas) over it for 2 s.
    private func blueUnder(_ overlay: URL, _ change: (inout Clip) -> Void = { _ in }) async throws -> Project {
        let mainURL = try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: blue)
        var project = Project()
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(mainURL)))
        let broll = project.addAsset(try await MediaProbe.probe(overlay))
        let added = project.addOverlay(of: broll, at: .zero)
        let id = try #require(added)
        project.updateOverlay(id) { overlay in
            overlay.start = .zero
            overlay.clip.duration = CMTime(value: 2, timescale: 1)
            change(&overlay.clip)
        }
        return project
    }

    @Test func theGreenScreenIsKeyedOut() async throws {
        // Green screen on top, the "person" (red) below.
        let url = try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: screen, bottomBGRA: red)
        let plain = try await frame(of: try await CompositionBuilder.build(try await blueUnder(url)), at: 0.5)
        #expect(Fixture.pixel(plain, x: 540, y: 400).g > 150)
        let project = try await blueUnder(url) { $0.cutout.key = ColorKey(color: RGBA(0.2, 0.75, 0.3)) }
        let keyed = try await frame(of: try await CompositionBuilder.build(project), at: 0.5)
        #expect(isBlue(Fixture.pixel(keyed, x: 540, y: 400)))
        #expect(isRed(Fixture.pixel(keyed, x: 540, y: 1500)))
    }

    @Test func aMaskKeepsItsShapeAndMovesWithThePicture() async throws {
        let url = try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: red)
        let project = try await blueUnder(url) { $0.cutout.mask = ClipMask(shape: .circle, size: 0.5, feather: 0) }
        let image = try await frame(of: try await CompositionBuilder.build(project), at: 0.5)
        #expect(isRed(Fixture.pixel(image, x: 540, y: 960)))
        #expect(isBlue(Fixture.pixel(image, x: 540, y: 300)))
        #expect(isBlue(Fixture.pixel(image, x: 100, y: 960)))

        // Inverted: the other way round.
        var inverted = project
        inverted.overlays[0].clip.cutout.mask?.inverted = true
        let flipped = try await frame(of: try await CompositionBuilder.build(inverted), at: 0.5)
        #expect(isBlue(Fixture.pixel(flipped, x: 540, y: 960)))
        #expect(isRed(Fixture.pixel(flipped, x: 540, y: 300)))

        // The picture moved right and made smaller: the circle goes with it.
        var moved = project
        moved.overlays[0].clip.placement = Placement(offsetX: 0.25, scale: 0.5)
        let image2 = try await frame(of: try await CompositionBuilder.build(moved), at: 0.5)
        #expect(isRed(Fixture.pixel(image2, x: 810, y: 960)))
        #expect(isBlue(Fixture.pixel(image2, x: 810, y: 960 - 200)))
        #expect(isBlue(Fixture.pixel(image2, x: 540, y: 960)))
    }

    @Test func everyMaskShapeKeepsItsMiddleOrItsTop() async throws {
        let url = try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: red)
        for shape in ClipMask.Shape.allCases {
            let project = try await blueUnder(url) { $0.cutout.mask = ClipMask(shape: shape, size: 0.5, feather: 0.05) }
            let image = try await frame(of: try await CompositionBuilder.build(project), at: 0.5)
            let kept = shape == .line ? (540, 500) : (540, 960)
            #expect(isRed(Fixture.pixel(image, x: kept.0, y: kept.1)), "\(shape) middle")
            #expect(isBlue(Fixture.pixel(image, x: 540, y: 1800)), "\(shape) bottom")
        }
    }

    @Test func blendModesMixIntoWhatIsUnder() async throws {
        // White disappears when darkening; black disappears when lightening.
        let whiteURL = try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: white)
        let darkened = try await blueUnder(whiteURL) { $0.cutout.blend = .multiply }
        #expect(isBlue(Fixture.pixel(try await frame(of: try await CompositionBuilder.build(darkened), at: 0.5), x: 540, y: 960)))
        let blackURL = try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: black)
        let lightened = try await blueUnder(blackURL) { $0.cutout.blend = .screen }
        #expect(isBlue(Fixture.pixel(try await frame(of: try await CompositionBuilder.build(lightened), at: 0.5), x: 540, y: 960)))
        // Red added to blue makes magenta.
        let redURL = try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: red)
        let added = try await blueUnder(redURL) { $0.cutout.blend = .add }
        let p = Fixture.pixel(try await frame(of: try await CompositionBuilder.build(added), at: 0.5), x: 540, y: 960)
        #expect(p.r > 200 && p.b > 200 && p.g < 60, "\(p)")
        // Normal still covers.
        let normal = try await blueUnder(redURL)
        #expect(isRed(Fixture.pixel(try await frame(of: try await CompositionBuilder.build(normal), at: 0.5), x: 540, y: 960)))
    }

    @Test func aColourFillsAroundAPictureThatDoesntCover() async throws {
        // Landscape, shown whole: bars above and below.
        let url = try await Fixture.video(width: 320, height: 180, seconds: 1, bgra: red)
        var project = Project()
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(url)))
        project.timeline.clips[0].framing = .fit
        project.timeline.clips[0].background = .color
        project.timeline.clips[0].backgroundColor = RGBA(1, 1, 0)
        let image = try await frame(of: try await CompositionBuilder.build(project), at: 0.5)
        let bar = Fixture.pixel(image, x: 540, y: 200)
        #expect(bar.r > 230 && bar.g > 230 && bar.b < 30)
        #expect(isRed(Fixture.pixel(image, x: 540, y: 960)))
    }

    @Test func aSeeThroughCopyPlaysInPlaceOfItsFile() async throws {
        let url = try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: red)
        // Instead of Vision: keep the left half of every frame.
        let copy = CutoutCache.copyURL(for: url, subject: .people, isImage: false)
        try await CutoutMaker.makeVideo(from: url, to: copy, subject: .people, matte: { image in
            let e = image.extent
            return CIImage(color: .white).cropped(to: CGRect(x: e.minX, y: e.minY, width: e.width / 2, height: e.height))
                .composited(over: CIImage(color: .black).cropped(to: e))
        })
        defer { try? FileManager.default.removeItem(at: copy) }
        let track = try #require(try await AVURLAsset(url: copy).loadTracks(withMediaType: .video).first)
        let range = try await track.load(.timeRange)
        #expect(abs(range.duration.seconds - 2) < 0.05)

        let project = try await blueUnder(url) { $0.cutout.removeBackground = .people }
        let image = try await frame(of: try await CompositionBuilder.build(project), at: 1)
        #expect(isRed(Fixture.pixel(image, x: 200, y: 960)))
        #expect(isBlue(Fixture.pixel(image, x: 880, y: 960)))
        // Without it, the clip plays its own file.
        let plain = try await blueUnder(url)
        #expect(isRed(Fixture.pixel(try await frame(of: try await CompositionBuilder.build(plain), at: 1), x: 880, y: 960)))
    }

    @Test func aTurnedVideoKeepsItsCutOutTheRightWayUp() async throws {
        // Stored landscape, top red and bottom blue, turned a quarter: on screen red is on the right.
        let url = try await Fixture.video(width: 320, height: 180, seconds: 1, bgra: red, bottomBGRA: red,
                                          transform: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 180, ty: 0))
        let copy = CutoutCache.copyURL(for: url, subject: .subject, isImage: false)
        // Keep the top half of the upright picture.
        try await CutoutMaker.makeVideo(from: url, to: copy, subject: .subject, matte: { image in
            let e = image.extent
            #expect(e.height > e.width)
            return CIImage(color: .white).cropped(to: CGRect(x: e.minX, y: e.midY, width: e.width, height: e.height / 2))
                .composited(over: CIImage(color: .black).cropped(to: e))
        })
        defer { try? FileManager.default.removeItem(at: copy) }
        let project = try await blueUnder(url) { $0.cutout.removeBackground = .subject }
        let image = try await frame(of: try await CompositionBuilder.build(project), at: 0.5)
        #expect(isRed(Fixture.pixel(image, x: 540, y: 400)))
        #expect(isBlue(Fixture.pixel(image, x: 540, y: 1500)))
    }

    @Test func aPictureCopyIsAPNGWithoutItsBackground() async throws {
        let url = try Fixture.picture(width: 400, height: 600, top: (255, 0, 0), bottom: (255, 0, 0))
        let copy = CutoutCache.copyURL(for: url, subject: .people, isImage: true)
        try await CutoutMaker.makePicture(from: url, to: copy, subject: .people, matte: { image in
            let e = image.extent
            return CIImage(color: .white).cropped(to: CGRect(x: e.minX, y: e.minY, width: e.width / 2, height: e.height))
                .composited(over: CIImage(color: .black).cropped(to: e))
        })
        defer { try? FileManager.default.removeItem(at: copy) }
        let project = try await blueUnder(url) { $0.cutout.removeBackground = .people }
        let image = try await frame(of: try await CompositionBuilder.build(project), at: 0.5)
        #expect(isRed(Fixture.pixel(image, x: 200, y: 960)))
        #expect(isBlue(Fixture.pixel(image, x: 880, y: 960)))
    }

    @Test func visionFindsNoPersonInAPlainColour() async throws {
        // A solid colour has nobody in it: the copy is made, and nothing of it shows.
        let url = try await Fixture.video(width: 180, height: 320, seconds: 1, bgra: red)
        let copy = CutoutCache.copyURL(for: url, subject: .people, isImage: false)
        try await CutoutMaker.makeVideo(from: url, to: copy, subject: .people)
        defer { try? FileManager.default.removeItem(at: copy) }
        let project = try await blueUnder(url) { $0.cutout.removeBackground = .people }
        let image = try await frame(of: try await CompositionBuilder.build(project), at: 0.5)
        #expect(!isRed(Fixture.pixel(image, x: 540, y: 960)))
    }
}
