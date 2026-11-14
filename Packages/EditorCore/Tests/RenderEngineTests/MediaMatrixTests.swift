@preconcurrency import AVFoundation
import EditorCore
import Testing

@testable import RenderEngine

/// The kinds of files people really import (F10 of research/engineering-excellence.md): each is
/// probed, played through the composition (checking that the right source frame is shown at each
/// moment) and exported (checking the file).
///
/// One test at a time: each writes and encodes videos, and running them all at once starved
/// the other export tests of the video encoders (they hit their time limits).
@MainActor
@Suite(.serialized)
struct MediaMatrixTests {
    /// One row of the matrix.
    struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        let spec: MediaFixture.Spec
        /// The marker shows the source frame (SDR only: HDR values are tone-mapped).
        var checksFrames = true

        var testDescription: String { name }
    }

    /// Portrait 9:16 pictures, so the frame fills the canvas and every band is easy to find.
    nonisolated static func portrait(_ change: (inout MediaFixture.Spec) -> Void = { _ in }) -> MediaFixture.Spec {
        var spec = MediaFixture.Spec(width: 216, height: 384, bands: [(0.3, 0.3, 0.3), (0.6, 0.2, 0.2), (0.5, 0.5, 0.5)])
        change(&spec)
        return spec
    }

    /// iPhone-style portrait: stored landscape, turned a quarter clockwise.
    nonisolated static func turned(width: Int, height: Int) -> CGAffineTransform {
        CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: CGFloat(height), ty: 0)
    }

    /// Like a screen recording: frames only when something changed, at uneven gaps.
    nonisolated static var screenRecordingTimes: [CMTime] {
        // Gaps in 1/6000 s: 1/60, 1/30, 1/20, 1/10, 1/45, 1/60, 1/5, 1/30.
        let gaps: [CMTimeValue] = [100, 200, 300, 600, 133, 100, 1200, 200]
        var times: [CMTime] = []
        var t: CMTimeValue = 0
        for i in 0..<36 {
            times.append(CMTime(value: t, timescale: 6000))
            t += gaps[i % gaps.count]
        }
        return times
    }

    nonisolated static let cases: [Case] = [
        Case(
            name: "HLG (iPhone HDR)",
            spec: portrait {
                $0.codec = .hevc; $0.tenBit = true; $0.colour = .hlg
            }, checksFrames: false),
        Case(
            name: "Dolby Vision 8.4",
            spec: portrait {
                $0.codec = .hevc; $0.tenBit = true; $0.colour = .hlg; $0.dolbyVision = true
            },
            checksFrames: false),
        Case(
            name: "HDR10 (PQ)",
            spec: portrait {
                $0.codec = .hevc; $0.tenBit = true; $0.colour = .pq
            }, checksFrames: false),
        Case(
            name: "10-bit SDR HEVC",
            spec: portrait {
                $0.codec = .hevc; $0.tenBit = true
            }),
        Case(name: "variable frame rate", spec: portrait { $0.frameTimes = screenRecordingTimes }),
        Case(name: "25 fps", spec: portrait { $0.frameRate = 25 }),
        Case(name: "29.97 fps", spec: portrait { $0.frameRate = 30000.0 / 1001 }),
        Case(name: "23.976 fps", spec: portrait { $0.frameRate = 24000.0 / 1001 }),
        Case(name: "60 fps", spec: portrait { $0.frameRate = 60 }),
        Case(
            name: "120 fps",
            spec: portrait {
                $0.frameRate = 120; $0.seconds = 0.6
            }),
        // (AVAssetWriter makes sizes even, so a truly odd size can't be written here.)
        Case(
            name: "turned, size not a multiple of 16",
            spec: portrait {
                $0.width = 382
                $0.height = 214
                $0.transform = turned(width: 382, height: 214)
            }),
        Case(
            name: "4K HEVC, turned",
            spec: portrait {
                $0.width = 3840
                $0.height = 2160
                $0.codec = .hevc
                $0.seconds = 0.4
                $0.transform = turned(width: 3840, height: 2160)
            }),
        Case(name: "sound at 44.1 kHz", spec: portrait { $0.audio = (44_100, 2) }),
        Case(name: "mono sound", spec: portrait { $0.audio = (48_000, 1) }),
        Case(name: "no sound track", spec: portrait { $0.audio = nil }),
        Case(
            name: "MP4 at 44.1 kHz mono",
            spec: portrait {
                $0.audio = (44_100, 1); $0.fileType = .mp4
            }),
    ]

    // MARK: Helpers

    private func frame(of built: PlayableComposition, at time: CMTime) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: built.composition)
        generator.videoComposition = built.videoComposition
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: time).image
    }

    /// Where a point of the stored picture lands on the canvas (main clip, fitted and centred).
    private func canvasPoint(_ stored: CGPoint, of spec: MediaFixture.Spec) -> (x: Int, y: Int) {
        let size = CGRect(x: 0, y: 0, width: spec.width, height: spec.height).applying(spec.transform)
        var shown = stored.applying(spec.transform)
        shown.x -= size.minX
        shown.y -= size.minY
        let canvas = Project.canvasSize
        let scale = min(canvas.width / abs(size.width), canvas.height / abs(size.height))
        let x = (canvas.width - abs(size.width) * scale) / 2 + shown.x * scale
        let y = (canvas.height - abs(size.height) * scale) / 2 + shown.y * scale
        return (Int(x), Int(y))
    }

    /// Which source frame (as `index % 8`) a canvas picture shows, from its marker.
    private func shownFrame(_ image: CGImage, spec: MediaFixture.Spec) -> Int {
        let bandHeight = max(2, (spec.height / spec.bands.count) & ~1)
        let bottom = Double(spec.bands.count - 1) * Double(bandHeight)
        let middle = CGPoint(x: Double(spec.width) / 4, y: (bottom + Double(spec.height)) / 2)
        let p = canvasPoint(middle, of: spec)
        return MediaFixture.markerFrame(luma: ColourPixels.raw(image, x: p.x, y: p.y).g / 255)
    }

    /// The source frame on screen at `seconds` into the file: the last one starting by then, with
    /// frame times rounded to 1/600 s as an AVComposition holds them (29.97 fps frames move by
    /// under a millisecond).
    private func expectedFrame(at seconds: Double, in spec: MediaFixture.Spec) -> Int {
        let times = spec.times.map { ($0.seconds * 600).rounded() / 600 }
        return (times.lastIndex { $0 <= seconds + 1e-6 } ?? 0) % 8
    }

    // MARK: The matrix

    @Test(arguments: cases)
    func playsAndExports(_ item: Case) async throws {
        let spec = item.spec
        let url = try await MediaFixture.write(spec)

        // Probing: the upright size, the length, the frame rate and whether there is sound.
        let media = try await MediaProbe.probe(url)
        let upright = CGRect(x: 0, y: 0, width: spec.width, height: spec.height).applying(spec.transform)
        #expect(media.displaySize == CGSize(width: abs(upright.width), height: abs(upright.height)))
        #expect(abs(media.duration.seconds - spec.duration.seconds) < 0.02)
        #expect(media.hasAudio == (spec.audio != nil))
        if spec.frameTimes == nil {
            #expect(abs((media.frameRate ?? 0) - spec.frameRate) < 0.05)
        }

        var project = Project()
        project.appendClip(of: project.addAsset(media))
        let built = try await CompositionBuilder.build(project)
        #expect(built.missingAssets.isEmpty)

        // The right picture at each moment: composition frames are 1/30 s apart, the file's aren't.
        let frames = Int(project.duration.seconds * 30)
        for k in Set([0, 1, 4, 7, frames / 2, frames - 2]).sorted() where k >= 0 && k < frames {
            let time = CMTime(value: CMTimeValue(k), timescale: 30)
            let image = try await frame(of: built, at: time)
            #expect(image.width == 1080 && image.height == 1920)
            if item.checksFrames {
                let shown = shownFrame(image, spec: spec)
                // Through the clip's own speed: footage filmed for slow motion starts slowed down.
                let source = project.timeline.clips[0].sourceTime(atOffset: time)
                #expect(shown == expectedFrame(at: source.seconds, in: spec), "frame \(k)")
            }
            // The middle band is drawn (not black): the picture is there.
            let band = canvasPoint(CGPoint(x: Double(spec.width) * 0.75, y: Double(spec.height) / 2), of: spec)
            #expect(ColourPixels.raw(image, x: band.x, y: band.y).r > 40)
        }

        // Export: 30 fps for the whole length, sound as AAC 48 kHz stereo when there is any.
        let out = FileManager.default.temporaryDirectory.appending(path: "matrix-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: out) }
        try await Exporter.export(project, to: out, evenOutLoudness: spec.audio != nil)
        let file = AVURLAsset(url: out)
        let video = try #require(try await file.loadTracks(withMediaType: .video).first)
        let (range, rate) = try await video.load(.timeRange, .nominalFrameRate)
        #expect(abs(range.duration.seconds - project.duration.seconds) < 1.0 / 30 + 0.001)
        #expect(abs(Double(rate) - 30) < 0.1)
        #expect(try await videoFrameCount(of: file) == frames)
        let audio = try await file.loadTracks(withMediaType: .audio)
        if spec.audio != nil {
            let track = try #require(audio.first)
            let description = try #require(try await track.load(.formatDescriptions).first)
            let basic = try #require(CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee)
            #expect(basic.mSampleRate == 48_000 && basic.mChannelsPerFrame == 2)
            #expect(try await loudestSample(of: file) > 0.1)
        } else if !audio.isEmpty {
            #expect(try await loudestSample(of: file) < 0.001)
        }
    }

    /// A clip from minute 9 of a 10-minute file starts on the right picture and exports.
    @Test func aClipLateInALongFile() async throws {
        var spec = MediaFixture.Spec(width: 72, height: 128, frameRate: 5, seconds: 600, bands: [(0.3, 0.3, 0.3), (0.5, 0.5, 0.5)])
        spec.audio = (48_000, 1)
        let url = try await MediaFixture.write(spec)
        let media = try await MediaProbe.probe(url)
        #expect(abs(media.duration.seconds - 600) < 0.3)
        var project = Project()
        let start = CMTime(value: 540, timescale: 1)
        project.appendClip(of: project.addAsset(media), part: CMTimeRange(start: start, duration: CMTime(value: 2, timescale: 1)))
        let built = try await CompositionBuilder.build(project)
        for k in [0, 3, 31] {
            let time = CMTime(value: CMTimeValue(k), timescale: 30)
            let image = try await frame(of: built, at: time)
            #expect(shownFrame(image, spec: spec) == expectedFrame(at: 540 + time.seconds, in: spec), "frame \(k)")
        }
        let out = FileManager.default.temporaryDirectory.appending(path: "matrix-long-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: out) }
        try await Exporter.export(project, to: out)
        #expect(try await videoFrameCount(of: AVURLAsset(url: out)) == 60)
    }

    /// An untagged SD file (no colour information, as some apps write): the decoder's guess
    /// (Rec. 601, SD primaries) is used, so it looks as it does in QuickTime.
    @Test func anUntaggedFileLooksAsInQuickTime() async throws {
        let url = try await Fixture.video(width: 180, height: 320, bgra: (40, 200, 60, 255), colorTagged: false)
        var project = Project()
        project.appendClip(of: project.addAsset(try await MediaProbe.probe(url)))
        let ours = ColourPixels.srgb(try await frame(of: CompositionBuilder.build(project), at: CMTime(value: 15, timescale: 30)), x: 540, y: 960)
        // QuickTime's picture: AVFoundation's own colour-managed frame of the file.
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        let theirs = ColourPixels.srgb(try await generator.image(at: CMTime(value: 1, timescale: 2)).image, x: 90, y: 160)
        #expect(abs(ours.r - theirs.r) < 6 && abs(ours.g - theirs.g) < 6 && abs(ours.b - theirs.b) < 6, "\(ours) vs \(theirs)")
    }

    // MARK: Reading files

    private func videoFrameCount(of asset: AVAsset) async throws -> Int {
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        reader.startReading()
        var count = 0
        while let sample = output.copyNextSampleBuffer() {
            if CMSampleBufferGetNumSamples(sample) > 0 { count += 1 }
        }
        return count
    }

    /// The loudest sample of the file's sound, 0…1.
    private func loudestSample(of asset: AVAsset) async throws -> Float {
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return 0 }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false,
            ])
        reader.add(output)
        reader.startReading()
        var loudest: Float = 0
        while let sample = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(sample) {
            var length = 0
            var pointer: UnsafeMutablePointer<CChar>?
            CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer)
            guard let pointer else { continue }
            pointer.withMemoryRebound(to: Float.self, capacity: length / 4) { floats in
                for i in 0..<(length / 4) { loudest = max(loudest, abs(floats[i])) }
            }
        }
        return loudest
    }
}
