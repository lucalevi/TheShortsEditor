@preconcurrency import AVFoundation
import CoreImage
import EditorCore
import ImageIO
import Testing
import VideoToolbox

@testable import RenderEngine

/// Colour from the files to the finished Short (F8 of research/engineering-excellence.md, see
/// `ColorPipeline`): ordinary video passes through untouched; HDR footage is tone-mapped the same
/// way wherever its frames are drawn; pictures, titles and picked colours are converted from
/// their own colour space; copies keep the source's colours; an HDR export stays HDR.
///
/// One test at a time: each writes and encodes videos, and running them all at once starved
/// the other export tests of the video encoders (they hit their time limits).
@MainActor
@Suite(.serialized)
struct ColorPipelineTests {
    /// Non-linear R′G′B′ of the bands: black, dark grey, HLG's reference white, peak, red, mid grey.
    static let bands: [(Double, Double, Double)] = [(0, 0, 0), (0.38, 0.38, 0.38), (0.75, 0.75, 0.75), (1, 1, 1), (0.75, 0, 0), (0.5, 0.5, 0.5)]

    private func spec(_ colour: MediaFixture.Colour, tenBit: Bool = true, dolbyVision: Bool = false) -> MediaFixture.Spec {
        var spec = MediaFixture.Spec(width: 108, height: 192, bands: Self.bands)
        spec.codec = tenBit ? .hevc : .h264
        spec.tenBit = tenBit
        spec.colour = colour
        spec.dolbyVision = dolbyVision
        return spec
    }

    /// The middle of band `index` on the canvas (right half: the left of the last band is the frame marker).
    private func band(_ index: Int, of image: CGImage) -> (r: Double, g: Double, b: Double) {
        let y = Int(Double(image.height) * (Double(index) * 32 + 16) / 192)
        return ColourPixels.raw(image, x: image.width * 3 / 4, y: y)
    }

    private func bands(of image: CGImage) -> [(r: Double, g: Double, b: Double)] {
        (0..<Self.bands.count).map { band($0, of: image) }
    }

    private func close(_ a: [(r: Double, g: Double, b: Double)], _ b: [(r: Double, g: Double, b: Double)], within tolerance: Double) -> Bool {
        zip(a, b).allSatisfy { abs($0.r - $1.r) <= tolerance && abs($0.g - $1.g) <= tolerance && abs($0.b - $1.b) <= tolerance }
    }

    private func project(of url: URL) async throws -> Project {
        var project = Project()
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(url)))
        return project
    }

    private let half = CMTime(value: 15, timescale: 30)

    // MARK: The ways a frame is drawn

    private func generatorFrame(_ built: PlayableComposition, at time: CMTime) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: built.composition)
        generator.videoComposition = built.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: time).image
    }

    /// The frame as the viewer shows it: from an `AVPlayer`.
    private func playerFrame(_ built: PlayableComposition, at time: CMTime) async throws -> CGImage {
        let item = built.makePlayerItem()
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        item.add(output)
        let player = AVPlayer(playerItem: item)
        for _ in 0..<500 where item.status != .readyToPlay { try await Task.sleep(for: .milliseconds(10)) }
        await player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        for _ in 0..<300 {
            if let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
                let image = CIImage(cvPixelBuffer: buffer)
                let space = image.colorSpace ?? ColorPipeline.output(.standard).space
                return try #require(CIContext().createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: space))
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("The player gave no frame")
        throw MediaFixture.WriteError(description: "no frame")
    }

    private func exportedFrame(_ project: Project, at time: CMTime, range: DynamicRange = .standard) async throws -> (CGImage, URL) {
        let url = FileManager.default.temporaryDirectory.appending(path: "colour-\(UUID().uuidString).mp4")
        try await Exporter.export(project, to: url, evenOutLoudness: false, range: range)
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        if range == .high { generator.dynamicRangePolicy = .matchSource }
        return (try await generator.image(at: time).image, url)
    }

    /// The file's first frame turned into Rec. 709 by VideoToolbox: the reference tone mapping.
    private func videoToolboxReference(_ url: URL) async throws -> CGImage {
        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange])
        reader.add(output)
        reader.startReading()
        let source = try #require(output.copyNextSampleBuffer().flatMap(CMSampleBufferGetImageBuffer))
        let converted = try #require(HDRConversion().standard(source))
        let image = CIImage(cvPixelBuffer: converted)
        return try #require(
            CIContext().createCGImage(image, from: image.extent, format: .RGBA16, colorSpace: ColorPipeline.output(.standard).space))
    }

    // MARK: Ordinary video

    @Test(arguments: [false, true])
    func ordinaryVideoPassesThroughUnchanged(tenBit: Bool) async throws {
        let url = try await MediaFixture.write(spec(.rec709, tenBit: tenBit))
        let project = try await project(of: url)
        let expected = Self.bands.map { (r: $0.0 * 255, g: $0.1 * 255, b: $0.2 * 255) }
        let shown = bands(of: try await generatorFrame(CompositionBuilder.build(project), at: half))
        #expect(close(shown, expected, within: 2), "\(shown)")
        let (exported, file) = try await exportedFrame(project, at: half)
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(close(bands(of: exported), expected, within: 2.5), "\(bands(of: exported))")
    }

    // MARK: HDR footage in a standard Short

    @Test(arguments: ["HLG", "Dolby Vision", "PQ"])
    func hdrLooksTheSameInTheViewerThumbnailsAndExport(kind: String) async throws {
        let url = try await MediaFixture.write(spec(kind == "PQ" ? .pq : .hlg, dolbyVision: kind == "Dolby Vision"))
        let project = try await project(of: url)
        let built = try await CompositionBuilder.build(project)
        let reference = bands(of: try await videoToolboxReference(url))
        let thumbnail = bands(of: try await generatorFrame(built, at: half))
        let viewer = bands(of: try await playerFrame(built, at: half))
        let (exportedImage, file) = try await exportedFrame(project, at: half)
        defer { try? FileManager.default.removeItem(at: file) }
        let exported = bands(of: exportedImage)
        #expect(close(thumbnail, reference, within: 2), "thumbnail \(thumbnail) vs \(reference)")
        #expect(close(viewer, reference, within: 2.5), "viewer \(viewer) vs \(reference)")
        #expect(close(exported, reference, within: 2.5), "export \(exported) vs \(reference)")
    }

    /// iPhone footage in an ordinary Short: neither washed out (HDR values shown as if they were
    /// ordinary ones) nor clipped (bright parts all one white).
    @Test func hlgIsNeitherWashedOutNorClipped() async throws {
        let url = try await MediaFixture.write(spec(.hlg))
        let shown = bands(of: try await generatorFrame(CompositionBuilder.build(project(of: url)), at: half))
        #expect(shown[0].g < 3)
        // Brighter steps stay brighter: dark grey < mid grey < reference white < peak.
        #expect(shown[1].g < shown[5].g && shown[5].g < shown[2].g && shown[2].g < shown[3].g - 40)
        #expect(shown[2].g > 140 && shown[3].g > 245)
        // Red stays red.
        #expect(shown[4].r > 150 && shown[4].g < 5 && shown[4].b < 5)
        // Shown as ordinary video, HLG's reference white would be 191 and its dark grey 97.
        #expect(abs(shown[1].g - 97) > 10)
    }

    @Test func aFreezeFrameOfAnHDRClipMatchesTheMovingClip() async throws {
        let url = try await MediaFixture.write(spec(.hlg))
        var project = try await project(of: url)
        let moving = bands(of: try await generatorFrame(CompositionBuilder.build(project), at: CMTime(value: 6, timescale: 30)))
        try #require(project.addFreezeFrame(at: CMTime(value: 6, timescale: 30)) != nil)
        let frozen = bands(of: try await generatorFrame(CompositionBuilder.build(project), at: CMTime(value: 10, timescale: 30)))
        #expect(close(frozen, moving, within: 2), "\(frozen) vs \(moving)")
    }

    // MARK: Pictures, titles and picked colours

    /// A PNG of one colour in `space`.
    private func picture(_ rgb: (CGFloat, CGFloat, CGFloat), in space: CGColorSpace) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "colour-\(UUID().uuidString).png")
        let context = try #require(
            CGContext(
                data: nil, width: 270, height: 480, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(colorSpace: space, components: [rgb.0, rgb.1, rgb.2, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: 270, height: 480))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    /// The colour `rgb` in `space` as sRGB 0…255.
    private func inSRGB(_ rgb: (CGFloat, CGFloat, CGFloat), from space: CGColorSpace) -> (r: Double, g: Double, b: Double) {
        let color = CGColor(colorSpace: space, components: [rgb.0, rgb.1, rgb.2, 1])!
        let converted = color.converted(to: ColorPipeline.sRGB, intent: .defaultIntent, options: nil)!.components!
        return (Double(converted[0]) * 255, Double(converted[1]) * 255, Double(converted[2]) * 255)
    }

    /// A photo looks on screen as it does in Preview, whatever its colour space.
    @Test(arguments: ["sRGB", "Display P3"])
    func aPhotoKeepsItsColours(space name: String) async throws {
        let space = try #require(CGColorSpace(name: name == "sRGB" ? CGColorSpace.sRGB : CGColorSpace.displayP3))
        let colour: (CGFloat, CGFloat, CGFloat) = (0.8, 0.45, 0.25)
        let project = try await project(of: try picture(colour, in: space))
        let shown = ColourPixels.srgb(try await generatorFrame(CompositionBuilder.build(project), at: half), x: 540, y: 960)
        let expected = inSRGB(colour, from: space)
        #expect(abs(shown.r - expected.r) < 3 && abs(shown.g - expected.g) < 3 && abs(shown.b - expected.b) < 3, "\(shown) vs \(expected)")
    }

    /// A title's box and a picked background colour look on screen as they were picked.
    @Test func pickedColoursLookAsPicked() async throws {
        let url = try await Fixture.video(width: 320, height: 180, bgra: (40, 40, 40, 255))
        var project = try await project(of: url)
        project.timeline.clips[0].background = .color
        project.timeline.clips[0].backgroundColor = RGBA(0.2, 0.6, 0.9)
        let id = project.addTitle(at: .zero, text: "Hello")
        let index = try #require(project.titles.firstIndex { $0.id == id })
        project.titles[index].look.boxColor = RGBA(0.9, 0.5, 0.2)
        project.titles[index].look.shadow = false
        let image = try await generatorFrame(CompositionBuilder.build(project), at: half)
        // Above the picture: the background colour.
        let behind = ColourPixels.srgb(image, x: 540, y: 300)
        #expect(abs(behind.r - 51) < 3 && abs(behind.g - 153) < 3 && abs(behind.b - 229.5) < 3, "\(behind)")
        // Inside the title's box, left of its text.
        let placement = try #require(TitleRenderer.placement(of: project.titles[index]))
        let box = ColourPixels.srgb(image, x: Int(placement.content.minX) + 6, y: Int(placement.content.midY))
        #expect(abs(box.r - 229.5) < 3 && abs(box.g - 127.5) < 3 && abs(box.b - 51) < 3, "\(box)")
    }

    // MARK: Copies the app makes

    private func colourProperties(of url: URL) async throws -> (primaries: String?, transfer: String?, depth: Int?) {
        let track = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first)
        let description = try #require(try await track.load(.formatDescriptions).first)
        let extensions = CMFormatDescriptionGetExtensions(description) as? [CFString: Any] ?? [:]
        return (
            extensions[kCMFormatDescriptionExtension_ColorPrimaries] as? String,
            extensions[kCMFormatDescriptionExtension_TransferFunction] as? String,
            extensions[kCMFormatDescriptionExtension_BitsPerComponent] as? Int
        )
    }

    @Test func aBackwardsCopyOfAnHDRClipKeepsItsColours() async throws {
        let url = try await MediaFixture.write(spec(.hlg))
        let copy = FileManager.default.temporaryDirectory.appending(path: "colour-back-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: copy) }
        try await Reverser.reverse(url, range: CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 1)), to: copy)
        let tags = try await colourProperties(of: copy)
        #expect(tags.primaries == (kCMFormatDescriptionColorPrimaries_ITU_R_2020 as String))
        #expect(tags.transfer == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String))
        let original = bands(of: try await generatorFrame(CompositionBuilder.build(project(of: url)), at: half))
        let backwards = bands(of: try await generatorFrame(CompositionBuilder.build(project(of: copy)), at: half))
        #expect(close(backwards, original, within: 3), "\(backwards) vs \(original)")
    }

    @Test func aSmoothSlowMotionCopyOfAnHDRClipKeepsItsColours() async throws {
        let url = try await MediaFixture.write(spec(.hlg))
        let recipe = FrameInterpolator.Recipe(range: CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 1)), factor: 2)
        let copy = try await FrameInterpolator.makeCopy(of: url, recipe: recipe)
        defer { try? FileManager.default.removeItem(at: copy) }
        let tags = try await colourProperties(of: copy)
        #expect(tags.transfer == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String))
        let original = bands(of: try await generatorFrame(CompositionBuilder.build(project(of: url)), at: half))
        let smooth = bands(of: try await generatorFrame(CompositionBuilder.build(project(of: copy)), at: half))
        #expect(close(smooth, original, within: 4), "\(smooth) vs \(original)")
    }

    @Test func aCutOutCopyIsTaggedLikeItsFile() async throws {
        let url = try await MediaFixture.write(spec(.hlg))
        let copy = FileManager.default.temporaryDirectory.appending(path: "colour-cut-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: copy) }
        try await CutoutMaker.makeVideo(from: url, to: copy, subject: .people) { image in
            CIImage(color: .white).cropped(to: image.extent)
        }
        let tags = try await colourProperties(of: copy)
        #expect(tags.transfer == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String))
        let original = bands(of: try await generatorFrame(CompositionBuilder.build(project(of: url)), at: half))
        let cut = bands(of: try await generatorFrame(CompositionBuilder.build(project(of: copy)), at: half))
        // 8-bit (HEVC with alpha), so a little further off.
        #expect(close(cut, original, within: 6), "\(cut) vs \(original)")
    }

    // MARK: HDR export

    /// The luma code (10 bits) of each band of the exported file's frame, read without conversion.
    private func lumaCodes(of url: URL) async throws -> [Int] {
        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: half, duration: CMTime(value: 1, timescale: 30))
        let output = AVAssetReaderTrackOutput(
            track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange])
        reader.add(output)
        reader.startReading()
        let buffer = try #require(output.copyNextSampleBuffer().flatMap(CMSampleBufferGetImageBuffer))
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = try #require(CVPixelBufferGetBaseAddressOfPlane(buffer, 0))
        let row = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        return (0..<Self.bands.count).map { index in
            let y = Int(1920 * (Double(index) * 32 + 16) / 192)
            return Int(base.advanced(by: y * row + 810 * 2).assumingMemoryBound(to: UInt16.self).pointee >> 6)
        }
    }

    @Test func anHDRExportStaysHDR() async throws {
        let url = try await MediaFixture.write(spec(.hlg))
        var project = try await project(of: url)
        // Then an ordinary clip of plain white.
        let white = try await MediaFixture.write(
            MediaFixture.Spec(width: 108, height: 192, bands: [(1, 1, 1), (1, 1, 1), (1, 1, 1), (1, 1, 1), (1, 1, 1), (1, 1, 1)]))
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(white)))
        let file = FileManager.default.temporaryDirectory.appending(path: "colour-hdr-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: file) }
        try await Exporter.export(project, to: file, evenOutLoudness: false, range: .high)

        let track = try #require(try await AVURLAsset(url: file).loadTracks(withMediaType: .video).first)
        let description = try #require(try await track.load(.formatDescriptions).first)
        #expect(CMFormatDescriptionGetMediaSubType(description) == kCMVideoCodecType_HEVC)
        let tags = try await colourProperties(of: file)
        #expect(tags.primaries == (kCMFormatDescriptionColorPrimaries_ITU_R_2020 as String))
        #expect(tags.transfer == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String))
        #expect(try await track.load(.mediaCharacteristics).contains(.containsHDRVideo))

        // The HDR clip's values come through as they were (10-bit luma codes, limited range).
        let codes = try await lumaCodes(of: file)
        for (index, band) in Self.bands.enumerated() where band.1 == band.0 {
            let expected = Int((64 + 876 * band.0).rounded())
            #expect(abs(codes[index] - expected) <= 6, "band \(index): \(codes[index]) vs \(expected)")
        }
        // Ordinary white sits at HLG's reference white (75%), leaving room above it for HDR.
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: file))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.dynamicRangePolicy = .matchSource
        let later = try await generator.image(at: CMTime(value: 45, timescale: 30)).image
        let hlgSpace = try #require(CGColorSpace(name: CGColorSpace.itur_2100_HLG))
        var value = [Float](repeating: 0, count: 4)
        let context = try #require(
            CGContext(
                data: &value, width: 1, height: 1, bitsPerComponent: 32, bytesPerRow: 16, space: hlgSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue))
        context.draw(later, in: CGRect(x: -540, y: -960, width: later.width, height: later.height))
        #expect(abs(Double(value[1]) - 0.75) < 0.03, "white in HLG: \(value[1])")
    }
}
