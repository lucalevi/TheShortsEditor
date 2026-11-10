@preconcurrency import AVFoundation
import EditorCore
import ImageIO
import Testing
@testable import RenderEngine

/// Saving a frame as a picture.
@MainActor
struct FinishingRenderTests {
    @Test func aFrameIsSavedAtFullSizeAsJPEGAndPNG() async throws {
        var project = Project()
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(try await Fixture.video(width: 180, height: 320, bgra: (0, 0, 220, 255)))))
        project.look = FilterChoice(.blackAndWhite)
        // Asking past the end gives the last frame.
        let image = try await FrameExport.frame(of: project, at: CMTime(value: 5, timescale: 1))
        #expect(image.width == 1080 && image.height == 1920)
        for format in FrameExport.Format.allCases {
            let url = FileManager.default.temporaryDirectory.appending(path: "frame-\(UUID().uuidString).\(format.type.preferredFilenameExtension!)")
            try FrameExport.write(image, to: url, format: format)
            let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            #expect(CGImageSourceGetType(source) as String? == format.type.identifier)
            let read = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(read.width == 1080 && read.height == 1920)
            // The look is in the picture: grey, not red.
            let p = Fixture.pixel(read, x: 540, y: 960)
            #expect(abs(Int(p.r) - Int(p.b)) < 10)
        }
    }

    @Test func writingWhereItCantFails() throws {
        let image = StillImages.image(at: try Fixture.picture(width: 10, height: 10, top: (1, 2, 3)))!
        #expect(throws: FrameExport.WriteError.self) {
            try FrameExport.write(image, to: URL(fileURLWithPath: "/nonexistent-folder/x.png"), format: .png)
        }
    }
}
