@preconcurrency import AVFoundation
import EditorCore
import Testing

@testable import RenderEngine

/// Stage L drawn: the cover picture has its big text where it was put.
@MainActor
struct CoverRenderTests {
    @Test func theCoverHasItsTextAtItsPlace() async throws {
        let url = try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: (0, 0, 255, 255))
        var project = Project()
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(url)))
        let plain = try await ProjectPoster.cover(of: project, ShortCover(time: CMTime(value: 1, timescale: 1)))
        #expect(plain.width == 1080 && plain.height == 1920)
        #expect(Fixture.whitePixels(plain, in: CGRect(x: 0, y: 0, width: 1080, height: 1920)) == 0)
        let cover = ShortCover(time: CMTime(value: 1, timescale: 1), text: "BIG", textPosition: 0.25)
        let image = try await ProjectPoster.cover(of: project, cover)
        let near = Fixture.whitePixels(image, in: CGRect(x: 0, y: 380, width: 1080, height: 200))
        let far = Fixture.whitePixels(image, in: CGRect(x: 0, y: 1200, width: 1080, height: 400))
        #expect(near > 50)
        #expect(far == 0)
    }
}
