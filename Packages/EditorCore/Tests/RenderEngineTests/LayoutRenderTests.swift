@preconcurrency import AVFoundation
import EditorCore
import Testing

@testable import RenderEngine

private let red: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 255, 255)
private let blue: (UInt8, UInt8, UInt8, UInt8) = (255, 0, 0, 255)

@MainActor
struct LayoutRenderTests {
    private func frame(of built: PlayableComposition, at seconds: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: built.composition)
        generator.videoComposition = built.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }

    private func isRed(_ p: (r: UInt8, g: UInt8, b: UInt8)) -> Bool { p.r > 200 && p.g < 60 && p.b < 60 }
    private func isBlue(_ p: (r: UInt8, g: UInt8, b: UInt8)) -> Bool { p.b > 200 && p.r < 60 && p.g < 60 }

    private func oneClip(_ url: URL) async throws -> Project {
        var project = Project()
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(url)))
        return project
    }

    /// How many pixels of `image` are close to `color` (r, g, b).
    private func count(_ image: CGImage, near color: (Int, Int, Int)) -> Int {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 0, to: data.count, by: 4).count {
            data[$0 + 3] > 200 && abs(Int(data[$0]) - color.0) < 40 && abs(Int(data[$0 + 1]) - color.1) < 40 && abs(Int(data[$0 + 2]) - color.2) < 40
        }
    }

    // MARK: Layouts

    @Test func splitScreenShowsBothClips() async throws {
        let main = try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: red)
        let other = try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: blue)
        var project = try await oneClip(main)
        let added = project.addOverlay(of: project.addAsset(try await MediaProbe.probe(other)), at: .zero)
        let id = try #require(added)
        project.updateOverlay(id) { $0.layout = .top }
        let image = try await frame(of: CompositionBuilder.build(project), at: 0.5)
        #expect(isBlue(Fixture.pixel(image, x: 540, y: 400)))
        #expect(isRed(Fixture.pixel(image, x: 540, y: 1500)))
    }

    // MARK: Reframing

    @Test func theSubjectIsFoundOnTheLeft() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "subject-\(UUID().uuidString).png")
        let width = 640, height = 360
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 1, green: 0.9, blue: 0.2, alpha: 1))
        context.fillEllipse(in: CGRect(x: 80, y: 120, width: 120, height: 120))
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        #expect(CGImageDestinationFinalize(destination))
        let media = try await MediaProbe.probe(url)
        let clip = Clip(assetID: media.id, sourceStart: .zero, duration: CMTime(value: 3, timescale: 1))
        let samples = try await Reframer.samples(for: clip, media: media)
        #expect(samples.count == 1)
        #expect(samples[0].x < 0.4)
    }
}
