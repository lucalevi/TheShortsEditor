@preconcurrency import AVFoundation
import EditorCore
import Testing
@testable import RenderEngine

private let red: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 255, 255)

@MainActor
struct ExporterTests {
    private func project(_ url: URL) async throws -> Project {
        var project = Project()
        let id = project.addAsset(try await MediaProbe.probe(url))
        project.appendClip(of: id)
        return project
    }

    private func outputURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "export-\(UUID().uuidString).mp4")
    }

    /// The names of the top-level boxes of an MP4 file, in order.
    private func topLevelBoxes(_ url: URL) throws -> [String] {
        let data = try Data(contentsOf: url)
        var names: [String] = []
        var offset = 0
        while offset + 8 <= data.count {
            var size = Int(data[offset..<offset + 4].reduce(0) { $0 << 8 | UInt32($1) })
            names.append(String(decoding: data[offset + 4..<offset + 8], as: UTF8.self))
            if size == 1 { size = Int(data[offset + 8..<offset + 16].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }) }
            guard size >= 8 else { break }
            offset += size
        }
        return names
    }

    @Test(.timeLimit(.minutes(1)))
    func exportsPicturesAndBRollWithTheirSound() async throws {
        // A 2 s video, then a 3 s picture; B-roll with its own sound over the start.
        let source = try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: red, toneFrom: 0)
        var project = try await project(source)
        let photo = project.addAsset(try await MediaProbe.probe(try Fixture.picture(width: 400, height: 300, top: (0, 0, 255))))
        project.appendClip(of: photo)
        let broll = project.addAsset(try await MediaProbe.probe(try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: red, toneFrom: 0)))
        let added = project.addOverlay(of: broll, at: .zero)
        let id = try #require(added)
        project.updateOverlay(id) { $0.clip.isMuted = false; $0.clip.placement = Placement(scale: 0.5) }

        let url = outputURL()
        try await Exporter.export(project, to: url) { _ in }
        let asset = AVURLAsset(url: url)
        #expect(abs(try await asset.load(.duration).seconds - 5) < 0.1)
        #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        // The picture (blue) shows at 3.5 s, over its blurred copy.
        let frame = try await generator.image(at: CMTime(value: 7, timescale: 2)).image
        let p = Fixture.pixel(frame, x: 540, y: 960)
        #expect(p.b > 200 && p.r < 60)
    }

    @Test(.timeLimit(.minutes(1)))
    func writesAFileYouTubeAccepts() async throws {
        let source = try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: red, toneFrom: 0)
        let url = outputURL()
        var reported: [Double] = []
        try await Exporter.export(try await project(source), to: url) { reported.append($0) }

        let asset = AVURLAsset(url: url)
        let video = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let (size, rate, formats) = try await video.load(.naturalSize, .nominalFrameRate, .formatDescriptions)
        #expect(size == CGSize(width: 1080, height: 1920))
        #expect(abs(rate - 30) < 0.5)
        #expect(formats.first.map(CMFormatDescriptionGetMediaSubType) == kCMVideoCodecType_H264)

        let audio = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let audioFormat = try #require(try await audio.load(.formatDescriptions).first)
        let stream = try #require(CMAudioFormatDescriptionGetStreamBasicDescription(audioFormat)?.pointee)
        #expect(stream.mFormatID == kAudioFormatMPEG4AAC)
        #expect(stream.mSampleRate == 48_000)
        #expect(stream.mChannelsPerFrame == 2)

        #expect(abs(try await asset.load(.duration).seconds - 2) < 0.1)
        // Fast start: the index comes before the media data.
        let boxes = try topLevelBoxes(url)
        #expect(try #require(boxes.firstIndex(of: "moov")) < (try #require(boxes.firstIndex(of: "mdat"))))
        #expect(reported.last == 1)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let frame = try await generator.image(at: CMTime(value: 1, timescale: 1)).image
        let pixel = Fixture.pixel(frame, x: 540, y: 960)
        #expect(pixel.r > 200 && pixel.g < 60 && pixel.b < 60)
    }

    @Test(.timeLimit(.minutes(1)))
    func captionsAreInTheExportedFile() async throws {
        let source = try await Fixture.video(width: 180, height: 320, bgra: red)
        var project = try await project(source)
        project.transcripts[project.assets[0].id] = Transcript(language: .english, words: [
            // At 0.5 s "file" is the current (yellow) word, so "Exported" is white.
            Word(text: "Exported", start: .zero, duration: CMTime(value: 2, timescale: 5)),
            Word(text: "file", start: CMTime(value: 2, timescale: 5), duration: CMTime(value: 3, timescale: 5)),
        ])
        let url = outputURL()
        try await Exporter.export(project, to: url)
        #expect(try await AVURLAsset(url: url).loadTracks(withMediaType: .audio).isEmpty)

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let frame = try await generator.image(at: CMTime(value: 1, timescale: 2)).image
        let middle = CGFloat(CaptionSettings().verticalPosition) * 1920
        #expect(Fixture.whitePixels(frame, in: CGRect(x: 150, y: middle - 150, width: 780, height: 300)) > 500)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellingRemovesThePartialFile() async throws {
        let source = try await Fixture.video(width: 180, height: 320, seconds: 4, bgra: red)
        let project = try await project(source)
        let url = outputURL()
        let task = Task { try await Exporter.export(project, to: url) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func openingLoudnessIsMeasured() async throws {
        let loud = try await project(try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: red, toneFrom: 0))
        let quiet = try await project(try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: red, toneFrom: 1.5))
        let silent = try await project(try await Fixture.video(width: 180, height: 320, bgra: red))
        let firstSecond = CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 1))
        #expect(try #require(try await AudioProbe.peak(of: loud, in: firstSecond)) > 0.3)
        #expect(try #require(try await AudioProbe.peak(of: quiet, in: firstSecond)) < ExportReview.silenceThreshold)
        #expect(try await AudioProbe.peak(of: silent, in: firstSecond) == nil)
    }

    @Test func levelsAreMeasuredPerFrame() async throws {
        let url = try await Fixture.video(width: 180, height: 320, seconds: 2, bgra: red, toneFrom: 1)
        let levels = try #require(try await AudioProbe.levels(of: url))
        #expect(abs(levels.decibels.count - 60) <= 2)
        #expect(levels.decibels[5...25].allSatisfy { $0 < -60 })
        #expect(levels.decibels[35...55].allSatisfy { $0 > -20 })
        let silent = try await Fixture.video(width: 180, height: 320, bgra: red)
        #expect(try await AudioProbe.levels(of: silent) == nil)
    }
}
