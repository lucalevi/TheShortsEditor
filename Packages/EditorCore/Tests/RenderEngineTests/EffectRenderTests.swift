@preconcurrency import AVFoundation
import CoreImage
import EditorCore
import Testing
@testable import RenderEngine

private let red: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 255, 255)
private let blue: (UInt8, UInt8, UInt8, UInt8) = (255, 0, 0, 255)

/// Stage J drawn: every effect changes the picture, where and how it should, and the new sounds.
@MainActor
struct EffectRenderTests {
    private func frame(of built: PlayableComposition, at seconds: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: built.composition)
        generator.videoComposition = built.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }

    private func t(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 600).snappedToFrame() }

    /// Red on top, blue below, 2 s, portrait (fills the canvas).
    private func twoColours() async throws -> Project {
        var project = Project()
        let url = try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: red, bottomBGRA: blue)
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(url)))
        return project
    }

    private func withEffect(_ kind: EffectKind, strength: Double = 1, part: EffectPart = .wholeClip, length: Double = 0.8) async throws -> PlayableComposition {
        var project = try await twoColours()
        project.timeline.clips[0].effects = [ClipEffect(kind, strength: strength, part: part, length: t(length))]
        return try await CompositionBuilder.build(project)
    }

    /// How different two pictures are, on average over a grid of points (0…255).
    private func difference(_ a: CGImage, _ b: CGImage) -> Double {
        var total = 0.0, n = 0.0
        for y in stride(from: 40, to: 1920, by: 80) {
            for x in stride(from: 40, to: 1080, by: 80) {
                let p = Fixture.pixel(a, x: x, y: y), q = Fixture.pixel(b, x: x, y: y)
                total += Double(abs(Int(p.r) - Int(q.r)) + abs(Int(p.g) - Int(q.g)) + abs(Int(p.b) - Int(q.b))) / 3
                n += 1
            }
        }
        return total / n
    }

    @Test func everyEffectChangesThePicture() async throws {
        // A detailed picture (grey blocks, a white square), so moves show too.
        var project = Project()
        let url = try await Fixture.shakyVideo(width: 180, height: 320, seconds: 2, offsets: [(0, 0)])
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(url)))
        let plain = try await frame(of: try await CompositionBuilder.build(project), at: 0.5)
        // Colour Pop leaves grey alone (it has its own test).
        for kind in EffectKind.allCases where kind != .colorPop {
            project.timeline.clips[0].effects = [ClipEffect(kind, strength: 1, part: kind == .flash || kind == .blur ? .start : .wholeClip, length: t(1.5))]
            let built = try await CompositionBuilder.build(project)
            // Glitch only shows on some frames: look at a few.
            var changed = 0.0
            for seconds in [0.03, 0.5, 0.53, 0.57, 0.6, 0.63] {
                changed = max(changed, difference(plain, try await frame(of: built, at: seconds)))
            }
            #expect(changed > 1.5, "\(kind) changed \(changed)")
        }
    }

    @Test func aFlashAtTheStartFadesAway() async throws {
        let built = try await withEffect(.flash, part: .start, length: 0.5)
        let first = Fixture.pixel(try await frame(of: built, at: 0), x: 540, y: 400)
        let after = Fixture.pixel(try await frame(of: built, at: 0.8), x: 540, y: 400)
        #expect(first.g > 180 && first.b > 180)
        #expect(after.g < 40 && after.r > 200)
    }

    @Test func theMirrorCopiesTheLeftHalf() async throws {
        var project = Project()
        // Left half red, right half blue: stored as top/bottom, turned a quarter.
        let url = try await Fixture.video(width: 320, height: 180, bgra: red, bottomBGRA: blue, transform: CGAffineTransform(rotationAngle: .pi / 2))
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(url)))
        let plain = try await frame(of: try await CompositionBuilder.build(project), at: 0.5)
        project.timeline.clips[0].effects = [ClipEffect(.mirror, strength: 1)]
        let mirrored = try await frame(of: try await CompositionBuilder.build(project), at: 0.5)
        let left = Fixture.pixel(mirrored, x: 200, y: 960), right = Fixture.pixel(mirrored, x: 880, y: 960)
        #expect(Fixture.pixel(plain, x: 200, y: 960) != Fixture.pixel(plain, x: 880, y: 960))
        #expect(abs(Int(left.r) - Int(right.r)) < 20 && abs(Int(left.b) - Int(right.b)) < 20)
    }

    @Test func colourPopKeepsStrongColoursAndGreysDullOnes() throws {
        let effect = ClipEffect(.colorPop, strength: 1)
        let moment = EffectMoment(effect: effect, seconds: 0, progress: 0, frame: 0)
        let region = CGRect(x: 0, y: 0, width: 10, height: 10)
        func popped(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> (Int, Int, Int) {
            let image = EffectRenderer.apply([moment], to: CIImage(color: CIColor(red: r, green: g, blue: b)).cropped(to: region), in: region)
            var pixel = [UInt8](repeating: 0, count: 4)
            CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
                .render(image, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
            return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
        }
        let strong = popped(0.9, 0.1, 0.1)
        #expect(strong.0 > 200 && strong.1 < 60)
        let dull = popped(0.6, 0.5, 0.45)
        #expect(abs(dull.0 - dull.2) < 6)
    }

    @Test func effectsFollowTheirClip() async throws {
        var project = try await twoColours()
        project.appendClip(of: project.timeline.clips[0].assetID)
        project.timeline.clips[1].effects = [ClipEffect(.flash, strength: 1, part: .start, length: t(0.5))]
        let built = try await CompositionBuilder.build(project)
        // No flash at the start of the Short; a flash where the second clip starts.
        #expect(Fixture.pixel(try await frame(of: built, at: 0), x: 540, y: 400).g < 40)
        #expect(Fixture.pixel(try await frame(of: built, at: 2), x: 540, y: 400).g > 180)
    }

    @Test func previewsAreDrawnForEveryEffect() throws {
        let still = try Fixture.picture(width: 160, height: 284, top: (220, 40, 40), bottom: (40, 40, 220))
        let image = try #require(StillImages.image(at: still))
        for kind in EffectKind.allCases {
            #expect(EffectRenderer.preview(image, kind: kind) != nil, "\(kind)")
        }
    }

    @Test func theNewSoundsAreAudible() throws {
        let new: [SoundEffect] = [.subDrop, .glitch, .drumRoll, .reverseCymbal, .countdown, .sparkle, .kaching, .vibrate, .dingDong, .recordScratch, .tada, .bubble]
        #expect(SoundEffect.allCases.count == 46)
        for effect in new {
            let samples = effect.samples()
            let loudest = samples.map(abs).max() ?? 0
            let rms = (samples.map { $0 * $0 }.reduce(0, +) / Float(max(samples.count, 1))).squareRoot()
            #expect(abs(loudest - 0.8) < 0.01, "\(effect)")
            #expect(rms > 0.03, "\(effect) rms \(rms)")
        }
    }
}

extension EffectRenderTests {
    @Test func aColourSplitStaysAsSolidAsThePicture() throws {
        let region = CGRect(x: 0, y: 0, width: 40, height: 40)
        let moment = EffectMoment(effect: ClipEffect(.rgbSplit, strength: 1), seconds: 0, progress: 0, frame: 0)
        let image = EffectRenderer.apply([moment], to: CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: region), in: region)
        // Laid over black, the middle (where all three channels meet) is the same grey, not darker or lighter.
        let over = image.composited(over: CIImage(color: .black).cropped(to: region))
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
            .render(over, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 20, y: 20, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        #expect(abs(Int(pixel[0]) - 128) < 6 && abs(Int(pixel[1]) - 128) < 6 && abs(Int(pixel[2]) - 128) < 6, "\(pixel)")
    }
}
