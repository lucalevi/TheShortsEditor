@preconcurrency import AVFoundation
import CoreImage
import CryptoKit
import EditorCore
import Foundation
import VideoToolbox

/// Smooth slow motion: a copy of (part of) a video with pictures made up in between the real
/// ones, so a slowed-down clip still shows a new picture every frame. Uses Apple's frame-rate
/// conversion (`VTFrameProcessor`, optical flow on this Mac's GPU); where that isn't available,
/// the pictures in between are blends of their neighbours. Made once, offline, kept in Caches,
/// like the cleaned-up voice. The copy has the original's timing (shifted to start at 0) and no
/// sound: the clip's sound still comes from the original.
public nonisolated enum FrameInterpolator {
    public enum InterpolationError: LocalizedError {
        case unreadable, failed

        public var errorDescription: String? {
            switch self {
            case .unreadable: "The video can't be read."
            case .failed: "The smooth slow motion couldn't be made."
            }
        }
    }

    /// What a copy holds: which part of the file, and how many pictures for each real one.
    public struct Recipe: Hashable, Sendable {
        public var range: CMTimeRange
        public var factor: Int
    }

    /// Files up to this long are done whole; of longer ones, the clip's part and a little more.
    static let wholeFileLimit = CMTime(value: 60, timescale: 1)
    static let margin = CMTime(value: 2, timescale: 1)
    static let maxFactor = 8
    static let maxSide: CGFloat = 1920

    static var folder: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appending(path: "Shorts Editor/Smooth Slow Motion", directoryHint: .isDirectory)
    }

    /// The copy `clip` needs, or nil when it doesn't need one (not slowed below what its file
    /// shows smoothly, a picture, a freeze frame).
    public static func recipe(for clip: Clip, media: MediaAsset) -> Recipe? {
        guard clip.smoothSlowMotion, media.hasVideo, !media.isImage, !clip.isFrozen else { return nil }
        let slowest = clip.speedCurve == nil ? clip.speed : clip.curveSteps.map(\.speed).min() ?? clip.speed
        let fileRate = media.frameRate ?? 30
        // Pictures needed per second of the file, against the pictures it has.
        let needed = Double(Project.frameRate) / max(slowest, 0.01)
        let factor = min(Int((needed / fileRate - 0.05).rounded(.up)), maxFactor)
        guard factor >= 2 else { return nil }
        let whole = CMTimeRange(start: .zero, duration: media.duration)
        let range = media.duration <= wholeFileLimit
            ? whole
            : CMTimeRange(start: clip.sourceStart - margin, end: clip.sourceRange.end + margin).intersection(whole)
        return Recipe(range: range, factor: factor)
    }

    /// Where the copy of `source` for `recipe` is kept.
    public static func copyURL(for source: URL, recipe: Recipe) -> URL {
        let values = try? source.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let key = "\(source.path)|\(values?.fileSize ?? 0)|\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)|"
            + "\(recipe.range.start.seconds)|\(recipe.range.duration.seconds)|\(recipe.factor)|v1"
        let digest = SHA256.hash(data: Data(key.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return folder.appending(path: "\(digest).mov")
    }

    /// The copy `clip` plays, when it needs one and it has been made: its URL and the part of the
    /// original it holds (its time 0 is `range.start` of the original).
    public static func existingCopy(for clip: Clip, media: MediaAsset) -> (url: URL, range: CMTimeRange)? {
        guard let recipe = recipe(for: clip, media: media) else { return nil }
        let url = copyURL(for: media.url, recipe: recipe)
        return FileManager.default.fileExists(atPath: url.path) ? (url, recipe.range) : nil
    }

    /// Whether this Mac makes the pictures in between with optical flow (else by blending).
    public static var usesOpticalFlow: Bool { VTFrameRateConversionConfiguration.isSupported }

    /// Makes the copy for `recipe` of the video at `url`, reporting progress 0…1.
    @concurrent
    public static func makeCopy(of url: URL, recipe: Recipe, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        let destination = copyURL(for: url, recipe: recipe)
        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        let asset = AVURLAsset(url: url)
        guard let video = try await asset.loadTracks(withMediaType: .video).first else { throw InterpolationError.unreadable }
        let (naturalSize, transform, rate, trackRange) = try await video.load(.naturalSize, .preferredTransform, .nominalFrameRate, .timeRange)
        let range = recipe.range.intersection(trackRange)
        guard range.duration > .zero, naturalSize.width > 0 else { throw InterpolationError.unreadable }

        let scale = min(1, maxSide / max(naturalSize.width, naturalSize.height))
        let width = max(2, Int((naturalSize.width * scale / 2).rounded()) * 2), height = max(2, Int((naturalSize.height * scale / 2).rounded()) * 2)
        let fileRate = rate > 0 ? Double(rate) : 30

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let temporary = folder.appending(path: UUID().uuidString + ".mov")
        let writer = try AVAssetWriter(outputURL: temporary, fileType: .mov)
        let outputRate = min(fileRate * Double(recipe.factor), 480)
        let bitRate = min(60_000_000, max(4_000_000, Int(Double(width * height) * min(outputRate, 120) * 0.15)))
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate, AVVideoMaxKeyFrameIntervalDurationKey: 1,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ] as [String: Any],
        ])
        input.expectsMediaDataInRealTime = false
        input.transform = transform
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ])
        guard writer.canAdd(input) else { throw InterpolationError.failed }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? InterpolationError.failed }
        writer.startSession(atSourceTime: .zero)

        // The pictures are read already at the copy's size, in the format the processor wants.
        let flow = usesOpticalFlow ? OpticalFlow(width: width, height: height) : nil
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = range
        let output = AVAssetReaderTrackOutput(track: video, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: flow != nil ? kCVPixelFormatType_64RGBAHalf : kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw InterpolationError.unreadable }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? InterpolationError.unreadable }

        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull(), .cacheIntermediates: false])
        var previous: (time: CMTime, buffer: CVPixelBuffer)?
        var lastWritten = CMTime(value: -1, timescale: 90000)

        func write(_ buffer: CVPixelBuffer, at time: CMTime) async throws {
            var time = (time - range.start).convertScale(90000, method: .roundHalfAwayFromZero)
            if time <= lastWritten { time = lastWritten + CMTime(value: 1, timescale: 90000) }
            while !input.isReadyForMoreMediaData {
                if writer.status == .failed { throw writer.error ?? InterpolationError.failed }
                try await Task.sleep(for: .milliseconds(2))
            }
            guard let pool = adaptor.pixelBufferPool else { throw writer.error ?? InterpolationError.failed }
            var target: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &target)
            guard let target else { throw InterpolationError.failed }
            context.render(CIImage(cvPixelBuffer: buffer), to: target)
            guard adaptor.append(target, withPresentationTime: time) else { throw writer.error ?? InterpolationError.failed }
            lastWritten = time
        }

        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let time = CMSampleBufferGetPresentationTimeStamp(sample)
            guard time >= range.start, time < range.end else { continue }
            if let (lastTime, lastBuffer) = previous {
                try await write(lastBuffer, at: lastTime)
                let phases = (1..<recipe.factor).map { Float($0) / Float(recipe.factor) }
                let between: [CVPixelBuffer]
                if let flow, let made = try? await flow.frames(between: lastBuffer, lastTime, and: buffer, time, phases: phases) {
                    between = made
                } else {
                    between = phases.compactMap { blend(lastBuffer, buffer, $0, context: context) }
                }
                for (phase, picture) in zip(phases, between) {
                    try await write(picture, at: lastTime + CMTimeMultiplyByFloat64(time - lastTime, multiplier: Double(phase)))
                }
            }
            previous = (time, buffer)
            progress(min(max((time - range.start).seconds / range.duration.seconds, 0), 0.99))
        }
        if let (lastTime, lastBuffer) = previous { try await write(lastBuffer, at: lastTime) }
        if reader.status == .failed { throw reader.error ?? InterpolationError.unreadable }
        flow?.finish()
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: temporary)
            throw writer.error ?? InterpolationError.failed
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
        progress(1)
        return destination
    }

    /// A picture `phase` of the way from `a` to `b`, by blending (when optical flow isn't available).
    private static func blend(_ a: CVPixelBuffer, _ b: CVPixelBuffer, _ phase: Float, context: CIContext) -> CVPixelBuffer? {
        let mixed = CIImage(cvPixelBuffer: a).applyingFilter("CIDissolveTransition", parameters: [
            "inputTargetImage": CIImage(cvPixelBuffer: b), "inputTime": phase,
        ])
        var target: CVPixelBuffer?
        CVPixelBufferCreate(nil, CVPixelBufferGetWidth(a), CVPixelBufferGetHeight(a), kCVPixelFormatType_32BGRA,
                            [kCVPixelBufferIOSurfacePropertiesKey: [String: Any]()] as CFDictionary, &target)
        guard let target else { return nil }
        context.render(mixed, to: target)
        return target
    }

    /// Apple's frame-rate conversion, one session for the whole copy.
    private final class OpticalFlow {
        let processor = VTFrameProcessor()
        let pool: CVPixelBufferPool
        var submittedBefore = false

        init?(width: Int, height: Int) {
            guard let configuration = VTFrameRateConversionConfiguration(
                frameWidth: width, frameHeight: height, usePrecomputedFlow: false,
                qualityPrioritization: .normal, revision: VTFrameRateConversionConfiguration.defaultRevision)
            else { return nil }
            var pool: CVPixelBufferPool?
            CVPixelBufferPoolCreate(nil, nil, configuration.destinationPixelBufferAttributes as CFDictionary, &pool)
            guard let pool, (try? processor.startSession(configuration: configuration)) != nil else { return nil }
            self.pool = pool
        }

        func frames(between a: CVPixelBuffer, _ timeA: CMTime, and b: CVPixelBuffer, _ timeB: CMTime, phases: [Float]) async throws -> [CVPixelBuffer]? {
            guard let source = VTFrameProcessorFrame(buffer: a, presentationTimeStamp: timeA),
                  let next = VTFrameProcessorFrame(buffer: b, presentationTimeStamp: timeB) else { return nil }
            var destinations: [VTFrameProcessorFrame] = []
            for phase in phases {
                var buffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
                let at = timeA + CMTimeMultiplyByFloat64(timeB - timeA, multiplier: Double(phase))
                guard let buffer, let frame = VTFrameProcessorFrame(buffer: buffer, presentationTimeStamp: at) else { return nil }
                destinations.append(frame)
            }
            guard let parameters = VTFrameRateConversionParameters(
                sourceFrame: source, nextFrame: next, opticalFlow: nil, interpolationPhase: phases,
                submissionMode: submittedBefore ? .sequential : .random, destinationFrames: destinations)
            else { return nil }
            submittedBefore = true
            try await processor.process(parameters: parameters)
            return destinations.map(\.buffer)
        }

        func finish() { processor.endSession() }
    }
}
