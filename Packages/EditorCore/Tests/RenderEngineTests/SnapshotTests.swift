@preconcurrency import AVFoundation
import CoreGraphics
import EditorCore
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import RenderEngine

/// The compositor's pictures for a few typical Shorts, compared with saved pictures
/// (`Snapshots/<name>.png`, a quarter of full size), so any change in what a Short looks like
/// shows up as a failing test and a picture to look at, not by chance on screen.
///
/// After an intended change, look at the new pictures (the failure says where they are), then
/// record them: `SHORTS_RECORD_SNAPSHOTS=1 swift test --filter SnapshotTests`, and commit them.
@MainActor
@Suite(.serialized)
struct SnapshotTests {
    static let folder = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Snapshots", directoryHint: .isDirectory)
    static let width = 270, height = 480

    private let red: (UInt8, UInt8, UInt8, UInt8) = (40, 40, 220, 255)
    private let blue: (UInt8, UInt8, UInt8, UInt8) = (220, 60, 30, 255)
    private let yellow: (UInt8, UInt8, UInt8, UInt8) = (30, 210, 230, 255)

    // MARK: The Shorts

    /// A landscape clip: placed in the middle over a blurred copy of itself.
    @Test func wideClipOverItsBlur() async throws {
        var project = Project()
        // Grey blocks and a white square: detail for the blur and the placing to show.
        let url = try await Fixture.shakyVideo(width: 320, height: 180, seconds: 1, offsets: [(0, 0)])
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(url)))
        try await expectSnapshot("wide-clip", of: project, at: 0.5)
    }

    /// A hook title and spoken-word captions over an upright clip.
    @Test func titleAndCaptions() async throws {
        var project = Project()
        let url = try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: blue, bottomBGRA: red)
        let id = project.addAsset(try await MediaProbe.probe(url))
        project.appendClip(of: id)
        project.addTitle(at: .zero, text: "Watch this")
        project.transcripts[id] = Transcript(
            language: .english,
            words: ["This", "is", "really", "fast"].enumerated().map { index, text in
                Word(text: text, start: CMTime(value: Int64(index), timescale: 2), duration: CMTime(value: 2, timescale: 5))
            })
        project.captions.style = .karaoke
        try await expectSnapshot("title-and-captions", of: project, at: 0.6)
    }

    /// A look, an effect and a filter over the whole Short.
    @Test func lookEffectAndFilter() async throws {
        var project = Project()
        let url = try await Fixture.video(width: 180, height: 320, seconds: 1, bgra: yellow, bottomBGRA: blue)
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(url)))
        project.timeline.clips[0].look = ClipLook(filter: FilterChoice(.vivid))
        project.timeline.clips[0].effects = [ClipEffect(.glitch, part: .wholeClip)]
        project.look = FilterChoice(.film)
        try await expectSnapshot("look-effect-filter", of: project, at: 0.5)
    }

    /// Two clips halfway through a dissolve.
    @Test func dissolveBetweenClips() async throws {
        var project = Project()
        let first = try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: red)
        let second = try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: blue)
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(first)))
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(second)))
        project.setTransition(ClipTransition(kind: .dissolve), after: project.timeline.clips[0].id)
        try await expectSnapshot("dissolve", of: project, at: 2)
    }

    /// B-roll over the main clip.
    @Test func brollOverTheMainClip() async throws {
        var project = Project()
        let main = try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: blue)
        let broll = try await Fixture.video(width: 320, height: 180, seconds: 1, bgra: yellow, bottomBGRA: red)
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(main)))
        let overlay = try #require(project.addOverlay(of: project.addAsset(try await MediaProbe.probe(broll)), at: CMTime(value: 1, timescale: 2)))
        // Smaller, turned and to one side, so the main clip shows around it.
        project.updateAnyClip(overlay) { clip in
            clip.placement.scale = 0.5
            clip.placement.rotation = 10
            clip.placement.offsetX = 0.15
        }
        try await expectSnapshot("broll", of: project, at: 1)
    }

    // MARK: Comparing

    /// Draws `project` at `seconds` through the compositor, as the viewer and export do.
    private func render(_ project: Project, at seconds: Double) async throws -> CGImage {
        let built = try await CompositionBuilder.build(project)
        let generator = AVAssetImageGenerator(asset: built.composition)
        generator.videoComposition = built.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }

    private func expectSnapshot(_ name: String, of project: Project, at seconds: Double, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        let actual = try Snapshot(scaling: try await render(project, at: seconds), width: Self.width, height: Self.height)
        let goldenURL = Self.folder.appending(path: "\(name).png")
        let recording = ProcessInfo.processInfo.environment["SHORTS_RECORD_SNAPSHOTS"] == "1"
        guard !recording, let golden = Snapshot(contentsOf: goldenURL) else {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try actual.write(to: goldenURL)
            if !recording {
                Issue.record("No saved picture for “\(name)” yet: recorded \(goldenURL.path). Look at it, then run again.", sourceLocation: sourceLocation)
            }
            return
        }
        let difference = actual.difference(from: golden)
        // Encoders and Core Image differ by a level or two between runs; text edges move a little
        // more. A changed layout, colour or effect is far above both.
        guard difference.mean > 1.5 || difference.changedShare > 0.01 else { return }
        let out = FileManager.default.temporaryDirectory.appending(path: "snapshots", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try actual.write(to: out.appending(path: "\(name)-actual.png"))
        try golden.write(to: out.appending(path: "\(name)-expected.png"))
        try difference.picture.write(to: out.appending(path: "\(name)-difference.png"))
        Issue.record(
            """
            “\(name)” looks different: mean difference \(String(format: "%.2f", difference.mean)) levels, \
            \(String(format: "%.1f", difference.changedShare * 100))% of pixels changed by more than 24 levels. \
            Pictures in \(out.path). If the change is intended: SHORTS_RECORD_SNAPSHOTS=1 swift test --filter SnapshotTests
            """, sourceLocation: sourceLocation)
    }
}

/// An 8-bit sRGB picture, its pixels in memory.
struct Snapshot {
    let width: Int, height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// `image` drawn at `width`×`height`.
    init(scaling image: CGImage, width: Int, height: Int) throws {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw Fixture.WriteError() }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        self.init(width: width, height: height, pixels: pixels)
    }

    init?(contentsOf url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
            let snapshot = try? Snapshot(scaling: image, width: image.width, height: image.height)
        else { return nil }
        self = snapshot
    }

    var image: CGImage? {
        var copy = pixels
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(
            data: &copy, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
    }

    func write(to url: URL) throws {
        guard let image, let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw Fixture.WriteError()
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Fixture.WriteError() }
    }

    struct Difference {
        /// Mean absolute difference of the colour channels, in levels (0…255).
        let mean: Double
        /// The share of pixels where some channel differs by more than 24 levels.
        let changedShare: Double
        /// White where the pictures differ, black where they match.
        let picture: Snapshot
    }

    func difference(from other: Snapshot) -> Difference {
        guard other.width == width, other.height == height else {
            return Difference(mean: 255, changedShare: 1, picture: self)
        }
        var total = 0, changed = 0
        var picture = [UInt8](repeating: 255, count: pixels.count)
        for pixel in stride(from: 0, to: pixels.count, by: 4) {
            var largest = 0
            for channel in 0..<3 {
                let delta = abs(Int(pixels[pixel + channel]) - Int(other.pixels[pixel + channel]))
                total += delta
                largest = max(largest, delta)
            }
            if largest > 24 { changed += 1 }
            let shade = UInt8(min(255, largest * 4))
            (picture[pixel], picture[pixel + 1], picture[pixel + 2]) = (shade, shade, shade)
        }
        let count = pixels.count / 4
        return Difference(
            mean: Double(total) / Double(count * 3), changedShare: Double(changed) / Double(count),
            picture: Snapshot(width: width, height: height, pixels: picture))
    }
}
