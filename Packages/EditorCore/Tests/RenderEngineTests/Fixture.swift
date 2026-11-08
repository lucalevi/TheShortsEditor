import AVFoundation
import CoreVideo

/// Writes small solid-colour videos for tests, so they don't depend on files on disk.
enum Fixture {
    struct WriteError: Error {}

    /// A video of one colour, or two when `bottomBGRA` is given (top half, then bottom half, as
    /// stored in the file). `transform` is the track's orientation, as an iPhone writes it.
    /// With `toneFrom`, the file also has sound: silence, then a loud 440 Hz tone from that second on.
    static func video(
        width: Int, height: Int, seconds: Int = 1,
        bgra: (UInt8, UInt8, UInt8, UInt8), bottomBGRA: (UInt8, UInt8, UInt8, UInt8)? = nil,
        transform: CGAffineTransform = .identity,
        toneFrom: Double? = nil
    ) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "fixture-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
        input.transform = transform
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        var audio: AVAssetWriterInput?
        if toneFrom != nil {
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1,
            ])
            audioInput.expectsMediaDataInRealTime = false
            writer.add(audioInput)
            audio = audioInput
        }
        guard writer.startWriting() else { throw writer.error ?? WriteError() }
        writer.startSession(atSourceTime: .zero)

        let buffer = try solidBuffer(width: width, height: height, bgra: bgra, bottom: bottomBGRA ?? bgra)
        // Feed whichever input is ready: the writer interleaves sound and picture, so waiting on
        // one while it wants the other would never finish.
        let frames = 30 * seconds
        var nextVideo = 0, nextAudio = audio == nil ? frames : 0
        while nextVideo < frames || nextAudio < frames {
            var progressed = false
            if nextVideo < frames, input.isReadyForMoreMediaData {
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(nextVideo), timescale: 30)) else {
                    throw writer.error ?? WriteError()
                }
                nextVideo += 1
                progressed = true
            }
            if let audio, let toneFrom, nextAudio < frames, audio.isReadyForMoreMediaData {
                guard audio.append(try toneBuffer(frame: nextAudio, from: toneFrom)) else { throw writer.error ?? WriteError() }
                nextAudio += 1
                progressed = true
                // Say so straight away, or the writer holds back the picture waiting for more sound.
                if nextAudio == frames { audio.markAsFinished() }
            }
            if writer.status == .failed { throw writer.error ?? WriteError() }
            if !progressed { try await Task.sleep(for: .milliseconds(2)) }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? WriteError() }
        return url
    }

    /// 1/30 s of 48 kHz mono sound: silent before `from` seconds, a tone after.
    private static func toneBuffer(frame: Int, from: Double) throws -> CMSampleBuffer {
        let count = 1600
        let first = frame * count
        var samples = [Int16](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(first + i) / 48_000
            if t >= from { samples[i] = Int16(sin(2 * .pi * 440 * t) * 20_000) }
        }
        var description = AudioStreamBasicDescription(
            mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0
        )
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &description, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        var block: CMBlockBuffer?
        let bytes = count * 2
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: bytes, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
        guard let format, let block else { throw WriteError() }
        _ = samples.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes) }
        var sample: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: count, presentationTimeStamp: CMTime(value: CMTimeValue(first), timescale: 48_000), packetDescriptions: nil, sampleBufferOut: &sample)
        guard let sample else { throw WriteError() }
        return sample
    }

    private static func solidBuffer(width: Int, height: Int, bgra: (UInt8, UInt8, UInt8, UInt8), bottom: (UInt8, UInt8, UInt8, UInt8)) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
        guard let buffer else { throw WriteError() }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        for y in 0..<height {
            for x in 0..<width {
                let p = base + y * bytesPerRow + x * 4
                (p[0], p[1], p[2], p[3]) = y < height / 2 ? bgra : bottom
            }
        }
        return buffer
    }

    /// How many pixels inside `rect` (origin top left) are close to white.
    static func whitePixels(_ image: CGImage, in rect: CGRect) -> Int {
        let width = Int(rect.width), height = Int(rect.height)
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: -rect.minX, y: -(CGFloat(image.height) - rect.maxY), width: CGFloat(image.width), height: CGFloat(image.height)))
        return stride(from: 0, to: data.count, by: 4).count { data[$0] > 220 && data[$0 + 1] > 220 && data[$0 + 2] > 220 }
    }

    /// RGBA of one pixel, with (0, 0) at the top left.
    static func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        var data = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return (data[0], data[1], data[2])
    }
}
