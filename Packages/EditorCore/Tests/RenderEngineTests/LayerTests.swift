@preconcurrency import AVFoundation
import EditorCore
import Testing
@testable import RenderEngine

private let red: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 255, 255)
private let blue: (UInt8, UInt8, UInt8, UInt8) = (255, 0, 0, 255)

/// Pictures, overlays, placement, motion and the blurred background, checked pixel by pixel.
@MainActor
struct LayerTests {
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
    private func isReddish(_ p: (r: UInt8, g: UInt8, b: UInt8)) -> Bool { p.r > 90 && p.r > p.g + 40 && p.r > p.b + 40 }

    /// A Short of one vertical video, red on top and blue below, `seconds` long.
    private func redOverBlue(seconds: Int = 1) async throws -> (Project, Clip.ID) {
        let url = try await Fixture.video(width: 180, height: 320, seconds: seconds, bgra: red, bottomBGRA: blue)
        var project = Project()
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(url)))
        return (project, project.timeline.clips[0].id)
    }

    // MARK: Pictures

    @Test func probeReadsAPicture() async throws {
        let url = try Fixture.picture(width: 400, height: 300, top: (255, 0, 0))
        let asset = try await MediaProbe.probe(url)
        #expect(asset.isImage && !asset.hasAudio)
        #expect(asset.displaySize == CGSize(width: 400, height: 300))
        let thumbnail = try await MediaProbe.thumbnail(for: asset)
        #expect(thumbnail.width == 320)
    }

    @Test func aPictureIsShownTheRightWayUp() async throws {
        let url = try Fixture.picture(width: 270, height: 480, top: (255, 0, 0), bottom: (0, 0, 255))
        var project = Project()
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(url)))
        let built = try await CompositionBuilder.build(project)
        #expect(abs(built.composition.duration.seconds - MediaAsset.imageClipDuration.seconds) < 0.05)
        let image = try await frame(of: built, at: 1)
        #expect(isRed(Fixture.pixel(image, x: 540, y: 300)))
        #expect(isBlue(Fixture.pixel(image, x: 540, y: 1600)))
    }

    @Test func aMissingPictureIsBlackAndReported() async throws {
        var project = Project()
        let id = project.addAsset(.image(url: URL(fileURLWithPath: "/nowhere/gone.png"), size: CGSize(width: 100, height: 100)))
        project.appendClip(of: id)
        let built = try await CompositionBuilder.build(project)
        #expect(built.missingAssets == [id])
        #expect(isBlack(Fixture.pixel(try await frame(of: built, at: 1), x: 540, y: 960)))
    }

    // MARK: Background

    @Test func blurredBackgroundFillsTheBars() async throws {
        let url = try await Fixture.video(width: 320, height: 180, bgra: red)
        var project = Project()
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(url)))
        #expect(project.timeline.clips[0].framing == .fit && project.timeline.clips[0].background == .blur)
        let image = try await frame(of: CompositionBuilder.build(project), at: 0.5)
        #expect(isReddish(Fixture.pixel(image, x: 540, y: 200)))
        #expect(isRed(Fixture.pixel(image, x: 540, y: 960)))
    }

    // MARK: Placement and motion

    @Test func placementMovesThePicture() async throws {
        var (project, id) = try await redOverBlue()
        // Normally blue at y 1100; moved down a quarter of the screen it shows the red half there.
        #expect(isBlue(Fixture.pixel(try await frame(of: CompositionBuilder.build(project), at: 0.5), x: 540, y: 1100)))
        project.updateAnyClip(id) { $0.placement = Placement(offsetY: 0.25) }
        let image = try await frame(of: CompositionBuilder.build(project), at: 0.5)
        #expect(isRed(Fixture.pixel(image, x: 540, y: 1100)))
        // What was uncovered at the top shows the blurred background, not black.
        #expect(!isBlack(Fixture.pixel(image, x: 540, y: 100)))
    }

    @Test func keyframesMoveThePictureOverTime() async throws {
        var (project, id) = try await redOverBlue(seconds: 2)
        project.updateAnyClip(id) { clip in
            clip.keyframes = [Keyframe(time: .zero, placement: .identity, easing: .linear),
                              Keyframe(time: CMTime(value: 2, timescale: 1), placement: Placement(offsetY: 0.25), easing: .linear)]
        }
        let built = try await CompositionBuilder.build(project)
        #expect(isBlue(Fixture.pixel(try await frame(of: built, at: 0.1), x: 540, y: 1100)))
        #expect(isRed(Fixture.pixel(try await frame(of: built, at: 1.9), x: 540, y: 1100)))
    }

    @Test func livePreviewIsDrawnWithoutRebuilding() async throws {
        let (project, id) = try await redOverBlue()
        let built = try await CompositionBuilder.build(project)
        LivePreview.set(Placement(offsetY: 0.25), for: id)
        defer { LivePreview.set(nil, for: id) }
        #expect(isRed(Fixture.pixel(try await frame(of: built, at: 0.5), x: 540, y: 1100)))
    }

    // MARK: Overlays

    @Test func anOverlayIsDrawnOverTheMainClipWhileItIsOn() async throws {
        let mainURL = try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: red)
        let brollURL = try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: blue)
        var project = Project()
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(mainURL)))
        let broll = project.addAsset(try await MediaProbe.probe(brollURL))
        let added = project.addOverlay(of: broll, at: CMTime(value: 1, timescale: 1))
        let id = try #require(added)
        // Small, in the top left corner: picture-in-picture.
        project.updateOverlay(id) { overlay in
            overlay.start = CMTime(value: 1, timescale: 1)
            overlay.clip.duration = CMTime(value: 1, timescale: 1)
            overlay.clip.placement = Placement(offsetX: -0.25, offsetY: -0.25, scale: 0.5)
        }
        let built = try await CompositionBuilder.build(project)
        #expect(built.videoComposition.instructions.count == 2)

        let before = try await frame(of: built, at: 0.5)
        #expect(isRed(Fixture.pixel(before, x: 270, y: 480)))
        let during = try await frame(of: built, at: 1.5)
        #expect(isBlue(Fixture.pixel(during, x: 270, y: 480)))
        #expect(isRed(Fixture.pixel(during, x: 810, y: 1440)))
    }

    @Test func aPictureCanBeAnOverlay() async throws {
        let (project0, _) = try await redOverBlue()
        var project = project0
        let photo = project.addAsset(try await MediaProbe.probe(try Fixture.picture(width: 200, height: 200, top: (0, 0, 255))))
        project.addOverlay(of: photo, at: .zero)
        let image = try await frame(of: CompositionBuilder.build(project), at: 0.5)
        // Fill screen: the square picture covers everything.
        #expect(isBlue(Fixture.pixel(image, x: 540, y: 300)))
    }

    @Test func overlappingOverlaysGetTheirOwnTracksAndTheLaterIsOnTop() async throws {
        let mainURL = try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: red)
        let a = try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: blue)
        let b = try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: (0, 255, 0, 255))
        var project = Project()
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(mainURL)))
        project.addOverlay(of: project.addAsset(try await MediaProbe.probe(a)), at: .zero)
        project.addOverlay(of: project.addAsset(try await MediaProbe.probe(b)), at: CMTime(value: 1, timescale: 1))
        let built = try await CompositionBuilder.build(project)
        #expect(built.composition.tracks(withMediaType: .video).count == 3)
        let p = Fixture.pixel(try await frame(of: built, at: 1.5), x: 540, y: 960)
        #expect(p.g > 200 && p.r < 60 && p.b < 60)
    }

    @Test func overlaySoundIsMixedOnlyWhenTurnedOn() async throws {
        let mainURL = try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: red, toneFrom: 0)
        let brollURL = try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: blue, toneFrom: 0)
        var project = Project()
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(mainURL)))
        let added = project.addOverlay(of: project.addAsset(try await MediaProbe.probe(brollURL)), at: .zero)
        let id = try #require(added)
        let muted = try await CompositionBuilder.build(project)
        #expect(muted.composition.tracks(withMediaType: .audio).count == 1)
        project.updateOverlay(id) { $0.clip.isMuted = false }
        let unmuted = try await CompositionBuilder.build(project)
        #expect(unmuted.composition.tracks(withMediaType: .audio).count == 2)
        #expect(unmuted.audioMix.inputParameters.count == 2)
    }

    @Test func filmstripHasAStillPerSecond() async throws {
        let url = try await Fixture.video(width: 180, height: 320, seconds: 3, bgra: red)
        let strip = try await MediaProbe.filmstrip(for: try await MediaProbe.probe(url), height: 60)
        #expect(strip.images.count == 3)
        #expect(strip.image(at: CMTime(value: 10, timescale: 1)) != nil)
    }
}
