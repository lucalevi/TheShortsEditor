@preconcurrency import AVFoundation
import EditorCore
import Testing

@testable import RenderEngine

private let red: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 255, 255)
private let blue: (UInt8, UInt8, UInt8, UInt8) = (255, 0, 0, 255)
private let green: (UInt8, UInt8, UInt8, UInt8) = (0, 255, 0, 255)

private typealias Pixel = (r: UInt8, g: UInt8, b: UInt8)

/// Transitions, freeze frames, gradual speed, see-through B-roll and backwards copies, checked
/// pixel by pixel.
@MainActor
struct TransitionsAndTimeRenderTests {
    private func frame(of built: PlayableComposition, at seconds: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: built.composition)
        generator.videoComposition = built.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }

    private func middle(_ built: PlayableComposition, at seconds: Double) async throws -> Pixel {
        Fixture.pixel(try await frame(of: built, at: seconds), x: 540, y: 960)
    }

    private func isRed(_ p: Pixel) -> Bool { p.r > 200 && p.g < 60 && p.b < 60 }
    private func isBlue(_ p: Pixel) -> Bool { p.b > 200 && p.r < 60 && p.g < 60 }
    private func isGreen(_ p: Pixel) -> Bool { p.g > 200 && p.r < 60 && p.b < 60 }
    private func isBlack(_ p: Pixel) -> Bool { p.r < 40 && p.g < 40 && p.b < 40 }

    private func t(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 600).snappedToFrame() }

    /// A red clip, then a blue one, a second each, with `kind` between them.
    private func redThenBlue(_ kind: TransitionKind?) async throws -> Project {
        var project = Project()
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(try await Fixture.video(width: 180, height: 320, bgra: red))))
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(try await Fixture.video(width: 180, height: 320, bgra: blue))))
        if let kind { project.setTransition(ClipTransition(kind: kind), after: project.timeline.clips[0].id) }
        return project
    }

    // MARK: Transitions

    @Test func aDissolveMixesTheTwoClipsAroundTheCut() async throws {
        let built = try await CompositionBuilder.build(try await redThenBlue(.dissolve))
        // The Short keeps its length.
        #expect(abs(built.composition.duration.seconds - 2) < 0.05)
        #expect(isRed(try await middle(built, at: 0.5)))
        #expect(isBlue(try await middle(built, at: 1.5)))
        let before = try await middle(built, at: 0.9), at = try await middle(built, at: 1.0), after = try await middle(built, at: 1.1)
        // More and more blue, less and less red, through the transition.
        #expect(before.r > at.r && at.r > after.r)
        #expect(before.b < at.b && at.b < after.b)
        #expect(at.r > 80 && at.r < 180 && at.b > 80 && at.b < 180)
        #expect(before.b > 20 && after.r > 20)
    }

    @Test func withoutATransitionTheCutIsHard() async throws {
        let built = try await CompositionBuilder.build(try await redThenBlue(nil))
        #expect(isRed(try await middle(built, at: 0.95)))
        #expect(isBlue(try await middle(built, at: 1.0)))
    }

    @Test func throughBlackAndFlashPassTheirColour() async throws {
        let dark = try await CompositionBuilder.build(try await redThenBlue(.throughBlack))
        #expect(isBlack(try await middle(dark, at: 1.0)))
        let flash = try await middle(try await CompositionBuilder.build(try await redThenBlue(.throughWhite)), at: 1.0)
        #expect(flash.r > 200 && flash.g > 200 && flash.b > 200)
    }

    @Test func slidesAndWipesMoveTheRightWay() async throws {
        let wipe = try await frame(of: try await CompositionBuilder.build(try await redThenBlue(.wipe)), at: 1.0)
        // Uncovered from the left: the new clip on the left, the old still on the right.
        #expect(isBlue(Fixture.pixel(wipe, x: 100, y: 960)))
        #expect(isRed(Fixture.pixel(wipe, x: 980, y: 960)))
        let slide = try await frame(of: try await CompositionBuilder.build(try await redThenBlue(.slide)), at: 1.0)
        // Pushed out to the left: the old clip is on the left, the new comes from the right.
        #expect(isRed(Fixture.pixel(slide, x: 100, y: 960)))
        #expect(isBlue(Fixture.pixel(slide, x: 980, y: 960)))
        let up = try await frame(of: try await CompositionBuilder.build(try await redThenBlue(.slideUp)), at: 1.0)
        #expect(isRed(Fixture.pixel(up, x: 540, y: 200)))
        #expect(isBlue(Fixture.pixel(up, x: 540, y: 1700)))
    }

    @Test(arguments: [TransitionKind.zoom, .whip])
    func theOtherTransitionsStartOnTheOldClipAndEndOnTheNew(kind: TransitionKind) async throws {
        let built = try await CompositionBuilder.build(try await redThenBlue(kind))
        let start = try await middle(built, at: 1.0 - 7.0 / 30), end = try await middle(built, at: 1.0 + 6.0 / 30)
        #expect(start.r > 150 && start.b < 100)
        #expect(end.b > 150 && end.r < 100)
    }

    @Test func aClipCarriesOnFromItsFileAfterTheCut() async throws {
        // A file that is red for a second, then green. Its first second is clip one; after the
        // cut, the transition shows what follows in the file (green), not the last red picture.
        let url = try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: red, laterBGRA: green, laterFrom: 1)
        var project = Project()
        let asset = project.addAsset(try await MediaProbe.probe(url))
        project.appendClip(of: asset, part: CMTimeRange(start: .zero, duration: t(1)))
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(try await Fixture.video(width: 180, height: 320, bgra: blue))))
        project.setTransition(ClipTransition(kind: .wipe), after: project.timeline.clips[0].id)
        let built = try await CompositionBuilder.build(project)
        let image = try await frame(of: built, at: 1.1)
        #expect(isGreen(Fixture.pixel(image, x: 1040, y: 960)))
        #expect(isBlue(Fixture.pixel(image, x: 40, y: 960)))
        // Before the cut the next clip has nothing earlier in its file, so it holds its first picture.
        let early = try await frame(of: built, at: 0.9)
        #expect(isRed(Fixture.pixel(early, x: 1040, y: 960)))
        #expect(isBlue(Fixture.pixel(early, x: 20, y: 960)))
    }

    @Test func transitionsAreInTheExport() async throws {
        let project = try await redThenBlue(.dissolve)
        let url = FileManager.default.temporaryDirectory.appending(path: "transition-\(UUID().uuidString).mp4")
        try await Exporter.export(project, to: url)
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let p = Fixture.pixel(try await generator.image(at: CMTime(value: 30, timescale: 30)).image, x: 540, y: 960)
        #expect(p.r > 60 && p.b > 60 && p.g < 60)
    }

    // MARK: Freeze frame

    @Test func aFreezeFrameHoldsThePictureSilently() async throws {
        let url = try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: red, toneFrom: 0, laterBGRA: blue, laterFrom: 1)
        var project = Project()
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(url)))
        project.addFreezeFrame(at: t(0.5))
        let built = try await CompositionBuilder.build(project)
        #expect(abs(built.composition.duration.seconds - 5) < 0.05)
        let moving = try await middle(built, at: 0.3), held = try await middle(built, at: 2)
        #expect(isRed(held))
        // The held picture looks exactly like the moving one.
        #expect(abs(Int(moving.r) - Int(held.r)) <= 3 && abs(Int(moving.g) - Int(held.g)) <= 3 && abs(Int(moving.b) - Int(held.b)) <= 3)
        #expect(isRed(try await middle(built, at: 3.6)))
        #expect(isBlue(try await middle(built, at: 4.2)))
        // No sound during the freeze: the file's sound is in two pieces around it.
        let sound = try #require(try await built.composition.loadTracks(withMediaType: .audio).first)
        let filled = sound.segments.filter { !$0.isEmpty }
        #expect(filled.count == 2)
        #expect(abs(filled[1].timeMapping.target.start.seconds - 3.5) < 0.05)
    }

    @Test func aFreezeFrameOfALaterMomentShowsThatMoment() async throws {
        let url = try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: red, laterBGRA: blue, laterFrom: 1)
        var project = Project()
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(url)))
        project.addFreezeFrame(at: t(1.5))
        #expect(isBlue(try await middle(try await CompositionBuilder.build(project), at: 3)))
        // At the very end it holds the last picture.
        var atEnd = Project()
        atEnd.appendClip(of: atEnd.addAsset(try await MediaProbe.probe(url)))
        atEnd.addFreezeFrame(at: atEnd.duration)
        #expect(isBlue(try await middle(try await CompositionBuilder.build(atEnd), at: 4)))
    }

    // MARK: Speed

    @Test func gradualSpeedKeepsTheLengthAndThePicture() async throws {
        let url = try await Fixture.video(width: 180, height: 320, seconds: 6, bgra: red, toneFrom: 0, laterBGRA: blue, laterFrom: 5)
        var project = Project()
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(url)))
        project.setSpeed(0.5, in: CMTimeRange(start: t(2), end: t(3))) // 2 + 2 + 3 s
        let built = try await CompositionBuilder.build(project)
        #expect(abs(built.composition.duration.seconds - 7) < 0.05)
        let video = try #require(try await built.composition.loadTracks(withMediaType: .video).first)
        // 6 + 11 + 6 stretches instead of three.
        #expect(video.segments.count == 23)
        // The file's fifth second (blue) still arrives exactly where it should: at 6 s.
        #expect(isRed(try await middle(built, at: 5.9)))
        #expect(isBlue(try await middle(built, at: 6.05)))
        #expect(isRed(try await middle(built, at: 2.0)))

        project.timeline.clips[1].smoothSpeed = false
        let plain = try await CompositionBuilder.build(project)
        #expect(try await plain.composition.loadTracks(withMediaType: .video).first?.segments.count == 3)
    }

    @Test func theProbeReadsTheFrameRate() async throws {
        let asset = try await MediaProbe.probe(try await Fixture.video(width: 180, height: 320, bgra: red))
        #expect(abs((asset.frameRate ?? 0) - 30) < 1)
        #expect(!asset.isSlowMotion)
    }

    // MARK: See-through B-roll

    @Test func bRollCanBeSeeThroughAndFade() async throws {
        var project = Project()
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: red))))
        let over = project.addAsset(try await MediaProbe.probe(try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: blue)))
        let added = project.addOverlay(of: over, at: .zero)
        let id = try #require(added)
        #expect(isBlue(try await middle(try await CompositionBuilder.build(project), at: 1)))

        project.updateOverlay(id) { $0.clip.placement.opacity = 0.5 }
        let half = try await middle(try await CompositionBuilder.build(project), at: 1)
        #expect(half.r > 90 && half.r < 165 && half.b > 90 && half.b < 165)

        project.updateOverlay(id) {
            $0.clip.placement.opacity = 1; $0.clip.pictureFadeIn = t(1); $0.clip.pictureFadeOut = t(0.5)
        }
        let built = try await CompositionBuilder.build(project)
        let first = try await middle(built, at: 0), mid = try await middle(built, at: 0.5), full = try await middle(built, at: 1.2),
            last = try await middle(built, at: 1.9)
        #expect(first.r > 200 && first.b < 50)
        #expect(mid.r > 90 && mid.b > 90)
        #expect(isBlue(full))
        #expect(last.r > 150 && last.b < 110)
    }

    // MARK: Backwards

    @Test func aBackwardsCopyStartsWithTheEnd() async throws {
        // Red and silent for a second, then blue with a tone.
        let url = try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: red, toneFrom: 1, laterBGRA: blue, laterFrom: 1)
        let copy = FileManager.default.temporaryDirectory.appending(path: "backwards-\(UUID().uuidString).mov")
        let original = try await MediaProbe.probe(url)
        try await Reverser.reverse(url, range: CMTimeRange(start: .zero, duration: original.duration), to: copy)
        let turned = try await MediaProbe.probe(copy)
        #expect(abs(turned.duration.seconds - 2) < 0.1)
        #expect(turned.hasAudio)
        #expect(turned.displaySize == original.displaySize)

        var project = Project()
        project.appendClip(of: project.addAsset(turned))
        let built = try await CompositionBuilder.build(project)
        #expect(isBlue(try await middle(built, at: 0.5)))
        #expect(isRed(try await middle(built, at: 1.5)))

        // The tone is now in the first second, the silence in the second.
        let measured: AudioLevels? = try await AudioProbe.levels(of: copy)
        let levels = try #require(measured)
        #expect(levels.decibels[10] > -20)
        #expect(levels.decibels[50] < -50)
    }

    @Test func partOfAFileCanBeTurnedRound() async throws {
        let url = try await Fixture.video(width: 180, height: 320, seconds: 3, bgra: red, laterBGRA: blue, laterFrom: 2)
        let copy = FileManager.default.temporaryDirectory.appending(path: "backwards-\(UUID().uuidString).mov")
        let range = CMTimeRange(start: t(1), end: t(2.5))
        try await Reverser.reverse(url, range: range, to: copy)
        var turned = try await MediaProbe.probe(copy)
        #expect(abs(turned.duration.seconds - 1.5) < 0.1)
        #expect(!turned.hasAudio)

        // A clip showing 1.5…2.5 of the file turns into the first second of the copy: blue, then red.
        var project = Project()
        let asset = project.addAsset(try await MediaProbe.probe(url))
        turned.reversedFrom = ReversedSource(assetID: asset, range: range)
        project.addAsset(turned)
        project.appendClip(of: asset, part: CMTimeRange(start: t(1.5), end: t(2.5)))
        let flipped = project.flipDirection(of: project.timeline.clips[0].id)
        #expect(flipped)
        #expect(project.timeline.clips[0].sourceStart == .zero)
        let built = try await CompositionBuilder.build(project)
        #expect(isBlue(try await middle(built, at: 0.2)))
        #expect(isRed(try await middle(built, at: 0.8)))
    }
}
