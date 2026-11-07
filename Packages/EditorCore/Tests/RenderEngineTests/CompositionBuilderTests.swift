@preconcurrency import AVFoundation
import EditorCore
import Testing
@testable import RenderEngine

private let red: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 255, 255)

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
}
