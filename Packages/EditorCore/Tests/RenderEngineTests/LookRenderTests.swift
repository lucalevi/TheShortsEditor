@preconcurrency import AVFoundation
import EditorCore
import Testing
@testable import RenderEngine

private typealias Pixel = (r: UInt8, g: UInt8, b: UInt8)

/// Colour, filters, the whole Short's filter, before/after and Stabilize, checked pixel by pixel.
/// Serialized: before/after and live looks are app-wide switches.
@MainActor
@Suite(.serialized)
struct LookRenderTests {
    private func frame(of built: PlayableComposition, at seconds: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: built.composition)
        generator.videoComposition = built.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }

    private func middle(_ project: Project, at seconds: Double = 0.5) async throws -> Pixel {
        Fixture.pixel(try await frame(of: try await CompositionBuilder.build(project), at: seconds), x: 540, y: 960)
    }

    /// One clip of a single colour (BGRA), filling the screen.
    private func clip(_ bgra: (UInt8, UInt8, UInt8, UInt8)) async throws -> Project {
        var project = Project()
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(try await Fixture.video(width: 180, height: 320, bgra: bgra))))
        return project
    }

    private func rgb(_ p: Pixel) -> RGB { RGB(Double(p.r) / 255, Double(p.g) / 255, Double(p.b) / 255) }
    private func close(_ a: Pixel, _ b: RGB, _ tolerance: Double = 0.04) -> Bool {
        let c = rgb(a)
        return abs(c.r - b.r) <= tolerance && abs(c.g - b.g) <= tolerance && abs(c.b - b.b) <= tolerance
    }

    @Test func colourSlidersDrawWhatTheModelSays() async throws {
        var project = try await clip((90, 110, 150, 255))
        let before = try await middle(project)
        let look = ClipLook(color: ColorAdjustments(exposure: 0.4, contrast: 0.3, saturation: 0.5, warmth: 0.4))
        project.updateLook(of: project.timeline.clips[0].id) { $0 = look }
        let after = try await middle(project)
        let expected = look.apply(rgb(before))
        #expect(close(after, expected), "drew \(after), expected \(expected)")
        #expect(rgb(after).luma > rgb(before).luma)
    }

    @Test func blackAndWhiteFilterTakesTheColourOut() async throws {
        var project = try await clip((0, 0, 220, 255))
        let id = project.timeline.clips[0].id
        project.updateLook(of: id) { $0.filter = FilterChoice(.blackAndWhite) }
        let grey = try await middle(project)
        #expect(abs(Int(grey.r) - Int(grey.g)) < 6 && abs(Int(grey.g) - Int(grey.b)) < 6)
        // Half strength: still reddish, but less.
        project.updateLook(of: id) { $0.filter = FilterChoice(.blackAndWhite, strength: 0.5) }
        let half = try await middle(project)
        #expect(half.r > half.g + 40 && half.r < 220)
    }

    @Test func theWholeShortsFilterIsDrawnOverEveryClip() async throws {
        var project = try await clip((0, 0, 220, 255))
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(try await Fixture.video(width: 180, height: 320, bgra: (220, 0, 0, 255)))))
        project.look = FilterChoice(.noir)
        for seconds in [0.5, 1.5] {
            let p = try await middle(project, at: seconds)
            #expect(abs(Int(p.r) - Int(p.g)) < 6 && abs(Int(p.g) - Int(p.b)) < 6, "colour left at \(seconds) s: \(p)")
        }
    }

    @Test func vignetteDarkensTheCorners() async throws {
        var project = try await clip((150, 150, 150, 255))
        project.updateLook(of: project.timeline.clips[0].id) { $0.filter = FilterChoice(.vintage) }
        let image = try await frame(of: try await CompositionBuilder.build(project), at: 0.5)
        let centre = Fixture.pixel(image, x: 540, y: 960), corner = Fixture.pixel(image, x: 20, y: 20)
        #expect(Int(corner.r) + 25 < Int(centre.r))
    }

    @Test func beforeAndAfterShowsTheOriginal() async throws {
        var project = try await clip((40, 160, 200, 255))
        let original = try await middle(project)
        project.updateLook(of: project.timeline.clips[0].id) { $0.filter = FilterChoice(.noir) }
        project.look = FilterChoice(.cool)
        LivePreview.showsOriginal = true
        defer { LivePreview.showsOriginal = false }
        let shown = try await middle(project)
        #expect(abs(Int(shown.r) - Int(original.r)) < 4 && abs(Int(shown.b) - Int(original.b)) < 4)
    }

    @Test func aLiveLookIsShownWithoutRebuilding() async throws {
        let project = try await clip((128, 128, 128, 255))
        let built = try await CompositionBuilder.build(project)
        let plain = Fixture.pixel(try await frame(of: built, at: 0.5), x: 540, y: 960)
        LivePreview.setLook(ClipLook(color: ColorAdjustments(exposure: 1)), for: project.timeline.clips[0].id)
        defer { LivePreview.clearAll() }
        let brighter = Fixture.pixel(try await frame(of: built, at: 0.5), x: 540, y: 960)
        #expect(Int(brighter.g) > Int(plain.g) + 40)
    }

    @Test func measuringAndSampling() throws {
        let url = try Fixture.picture(width: 200, height: 100, top: (250, 10, 10), bottom: (10, 10, 250))
        let image = StillImages.image(at: url)!
        let pixels = LookRenderer.pixels(of: image, maxSide: 50)
        #expect(pixels.count == 50 * 25)
        let stats = FrameStats(pixels: pixels)!
        #expect(stats.mean.r > 0.4 && stats.mean.b > 0.4 && stats.mean.g < 0.1)
        let top = LookRenderer.sample(image, at: CGPoint(x: 100, y: 20))!
        let bottom = LookRenderer.sample(image, at: CGPoint(x: 100, y: 80))!
        #expect(top.r > 0.9 && top.b < 0.1)
        #expect(bottom.b > 0.9 && bottom.r < 0.1)
    }

    @Test func filterPreviewsAreMadeForTheGrid() throws {
        let url = try Fixture.picture(width: 90, height: 160, top: (200, 60, 40))
        let image = StillImages.image(at: url)!
        let preview = LookRenderer.preview(image, look: ClipLook(filter: FilterChoice(.blackAndWhite)))!
        #expect(preview.width == 90 && preview.height == 160)
        let p = Fixture.pixel(preview, x: 45, y: 40)
        #expect(abs(Int(p.r) - Int(p.b)) < 8)
    }

    // MARK: Stabilize

    /// Shakes ±8 pixels left and right (and ±4 up and down) every other frame.
    private let shake: [(Int, Int)] = (0..<60).map { $0.isMultiple(of: 2) ? (8, 4) : (-8, -4) }

    @Test func analysisFindsHowThePictureMoves() async throws {
        let url = try await Fixture.shakyVideo(offsets: shake)
        let path = try await Stabilizer.analyse(url)
        #expect(path.positions.count == 60)
        #expect(abs(path.interval - 1.0 / 30) < 0.001)
        // From frame 0 (+8, +4) to frame 1 (−8, −4) the content moved 16 left and 8 up.
        for i in 1..<20 {
            let expected = i.isMultiple(of: 2) ? (0.0, 0.0) : (-16.0, -8.0)
            #expect(abs(path.positions[i].x * 320 - expected.0) < 1.5, "x at \(i): \(path.positions[i].x * 320)")
            #expect(abs(path.positions[i].y * 180 - expected.1) < 1.5, "y at \(i): \(path.positions[i].y * 180)")
        }
    }

    @Test func stabilizeHoldsTheContentStill() async throws {
        let url = try await Fixture.shakyVideo(offsets: shake)
        var project = Project()
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(url)))
        let id = project.timeline.clips[0].id

        func spread(_ project: Project) async throws -> Double {
            let built = try await CompositionBuilder.build(project)
            var xs: [Double] = []
            for index in 20..<26 {
                let image = try await frame(of: built, at: (Double(index) + 0.5) / 30)
                xs.append(try #require(Fixture.whiteCentre(image)).x)
            }
            return xs.max()! - xs.min()!
        }
        let shaky = try await spread(project)
        project.updateAnyClip(id) { $0.steadiness = 1 }
        // Not measured yet: drawn as before.
        ShakeCacheTestHook.forget(url)
        #expect(abs(try await spread(project) - shaky) < 2)
        _ = try await ShakeCache.measure(url)
        let steadied = try await spread(project)
        #expect(shaky > 40, "shaky \(shaky)")
        #expect(steadied < shaky / 5, "shaky \(shaky), steadied \(steadied)")
    }
}

/// Lets a test start from an unmeasured file.
@MainActor
enum ShakeCacheTestHook {
    static func forget(_ url: URL) {
        try? FileManager.default.removeItem(at: ShakeCache.fileURL(for: url))
    }
}
