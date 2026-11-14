@preconcurrency import AVFoundation
import EditorCore
import Foundation

/// Makes a copy of (part of) a video that plays backwards, picture and sound. AVFoundation can't
/// play a file backwards inside a composition, so a clip that plays backwards points at such a
/// copy instead (see `ReversedSource`). Made once, offline, like the cleaned-up voice.
public nonisolated enum Reverser {
    public enum ReverseError: LocalizedError {
        case unreadable
        case failed

        public var errorDescription: String? {
            switch self {
            case .unreadable: "The video can't be read."
            case .failed: "The backwards copy couldn't be made."
            }
        }
    }

    /// The longest side of the copy, in pixels: plenty for a 1080×1920 Short.
    static let maxSide: CGFloat = 1920
    /// How much decoded picture is held in memory at once, in bytes.
    static let chunkBytes = 160_000_000

    /// Writes `range` of the video at `url`, backwards, to `destination` (a .mov), reporting
    /// progress 0…1. The first picture of the copy is the last one of the range.
    @concurrent
    public static func reverse(
        _ url: URL, range: CMTimeRange, to destination: URL,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws {
        let asset = AVURLAsset(url: url)
        guard let video = try await asset.loadTracks(withMediaType: .video).first else { throw ReverseError.unreadable }
        let (naturalSize, transform, rate, trackRange) = try await video.load(.naturalSize, .preferredTransform, .nominalFrameRate, .timeRange)
        let range = range.intersection(trackRange)
        guard range.duration > .zero, naturalSize.width > 0, naturalSize.height > 0 else { throw ReverseError.unreadable }
        let frameRate = rate > 0 ? Double(rate) : 30
        let frameDuration = CMTime(seconds: 1 / frameRate, preferredTimescale: 90000)

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let writer = try AVAssetWriter(outputURL: destination, fileType: .mov)

        let scale = min(1, maxSide / max(naturalSize.width, naturalSize.height))
        let width = max(2, Int((naturalSize.width * scale / 2).rounded()) * 2), height = max(2, Int((naturalSize.height * scale / 2).rounded()) * 2)
        let bitRate = min(40_000_000, max(2_000_000, Int(Double(width * height) * min(frameRate, 60) * 0.22)))
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: bitRate,
                    AVVideoMaxKeyFrameIntervalDurationKey: 1,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                ] as [String: Any],
            ])
        videoInput.expectsMediaDataInRealTime = false
        videoInput.transform = transform
        guard writer.canAdd(videoInput) else { throw ReverseError.failed }
        writer.add(videoInput)

        // The sound, turned round in memory (16-bit stereo: about 11 MB a minute).
        var sound = try await reversedSound(of: asset, range: range)
        var audioInput: AVAssetWriterInput?
        if sound != nil {
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: soundRate, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192_000,
                ])
            input.expectsMediaDataInRealTime = false
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            } else {
                sound = nil
            }
        }

        guard writer.startWriting() else { throw writer.error ?? ReverseError.failed }
        writer.startSession(atSourceTime: .zero)

        // The picture: read a short stretch at a time from the end, and write each backwards.
        let bytesPerFrame = Int(naturalSize.width * naturalSize.height * 1.5)
        let framesPerChunk = max(4, min(60, chunkBytes / max(bytesPerFrame, 1)))
        let chunkLength = CMTime(seconds: Double(framesPerChunk) / frameRate, preferredTimescale: 90000)
        var chunkEnd = range.end
        var pending: [(time: CMTime, buffer: CVPixelBuffer)] = []
        var lastWritten = CMTime(value: -1, timescale: 90000)
        var videoDone = false
        var soundOffset = 0
        let soundBytes = sound?.count ?? 0
        var audioDone = audioInput == nil

        while !videoDone || !audioDone {
            try Task.checkCancellation()
            var progressed = false
            if !videoDone, videoInput.isReadyForMoreMediaData {
                if pending.isEmpty, chunkEnd > range.start {
                    let chunkStart = max(range.start, chunkEnd - chunkLength)
                    pending = try frames(of: video, in: asset, from: chunkStart, to: chunkEnd)
                    chunkEnd = chunkStart
                    progress(min(max((range.end - chunkEnd).seconds / range.duration.seconds, 0), 1))
                }
                if let frame = pending.popLast() {
                    // The picture that ended last comes first.
                    var time = max(range.end - frame.time - frameDuration, .zero)
                    if time <= lastWritten { time = lastWritten + CMTime(value: 1, timescale: 90000) }
                    guard let sample = sampleBuffer(frame.buffer, at: time), videoInput.append(sample) else { throw writer.error ?? ReverseError.failed }
                    lastWritten = time
                    progressed = true
                } else if chunkEnd <= range.start {
                    videoInput.markAsFinished()
                    videoDone = true
                    progressed = true
                }
            }
            if !audioDone, let audioInput, let sound, audioInput.isReadyForMoreMediaData {
                let count = min(soundBytes - soundOffset, 4096 * 4)
                if count > 0, let sample = soundBuffer(sound, offset: soundOffset, count: count) {
                    guard audioInput.append(sample) else { throw writer.error ?? ReverseError.failed }
                    soundOffset += count
                }
                if count <= 0 || soundOffset >= soundBytes {
                    // Said straight away, or the writer holds the picture back waiting for more sound.
                    audioInput.markAsFinished()
                    audioDone = true
                }
                progressed = true
            }
            if writer.status == .failed { throw writer.error ?? ReverseError.failed }
            if !progressed { try await Task.sleep(for: .milliseconds(2)) }
        }
        await writer.finishWriting()
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: destination)
            throw writer.error ?? ReverseError.failed
        }
        progress(1)
    }

    /// The decoded pictures that start in `from ..< to`, in order.
    private static func frames(of track: AVAssetTrack, in asset: AVAsset, from: CMTime, to: CMTime) throws -> [(time: CMTime, buffer: CVPixelBuffer)] {
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: from, end: to)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw ReverseError.unreadable }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? ReverseError.unreadable }
        var result: [(time: CMTime, buffer: CVPixelBuffer)] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let time = CMSampleBufferGetPresentationTimeStamp(sample)
            // A reader can hand over a picture from just outside the stretch: it belongs to the next one.
            if time >= from, time < to { result.append((time, buffer)) }
        }
        if reader.status == .failed { throw reader.error ?? ReverseError.unreadable }
        return result
    }

    private static func sampleBuffer(_ buffer: CVPixelBuffer, at time: CMTime) -> CMSampleBuffer? {
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format)
        guard let format else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: nil, imageBuffer: buffer, formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample)
        return sample
    }

    // MARK: Sound

    private static let soundRate = 48_000.0

    /// The sound of `range` as 16-bit stereo at 48 kHz, last sample first. Nil without sound.
    private static func reversedSound(of asset: AVAsset, range: CMTimeRange) async throws -> Data? {
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return nil }
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = range
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: soundRate, AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
            ])
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        var data = Data()
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var bytes = [UInt8](repeating: 0, count: length)
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: &bytes)
            data.append(contentsOf: bytes)
        }
        let frames = data.count / 4
        guard frames > 0 else { return nil }
        var turned = Data(count: frames * 4)
        data.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
            turned.withUnsafeMutableBytes { (target: UnsafeMutableRawBufferPointer) in
                let from = source.bindMemory(to: UInt32.self), to = target.bindMemory(to: UInt32.self)
                // A frame is two 16-bit samples (left, right): four bytes moved together.
                for i in 0..<frames { to[i] = from[frames - 1 - i] }
            }
        }
        return turned
    }

    private static func soundBuffer(_ data: Data, offset: Int, count: Int) -> CMSampleBuffer? {
        var description = AudioStreamBasicDescription(
            mSampleRate: soundRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 2, mBitsPerChannel: 16, mReserved: 0
        )
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: nil, asbd: &description, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format
        )
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: count, blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: count,
            flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
        guard let format, let block else { return nil }
        let status = data.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress! + offset, blockBuffer: block, offsetIntoDestination: 0, dataLength: count)
        }
        guard status == kCMBlockBufferNoErr else { return nil }
        var sample: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: count / 4,
            presentationTimeStamp: CMTime(value: CMTimeValue(offset / 4), timescale: CMTimeScale(soundRate)),
            packetDescriptions: nil, sampleBufferOut: &sample)
        return sample
    }
}
