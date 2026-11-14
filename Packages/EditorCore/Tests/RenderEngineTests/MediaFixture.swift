@preconcurrency import AVFoundation
import CoreVideo
import VideoToolbox

/// Videos like the ones people really import: HDR from an iPhone (HLG, Dolby Vision), 10-bit,
/// odd or changing frame rates, turned, 4K HEVC, sound at 44.1 kHz or in mono, or none at all.
/// Written here, so the tests need no media files.
///
/// The picture is made of horizontal bands of exact colours (top to bottom, as stored), written
/// straight as Y′CbCr code values so nothing between us and the encoder changes them. The band
/// on the left of the bottom row says which frame it is: its brightness steps through 8 levels,
/// one per frame (`marker`), so a test can tell which source frame was shown.
enum MediaFixture {
    struct WriteError: Error, CustomStringConvertible {
        let description: String
    }

    /// How the picture's values are meant: primaries, transfer function and Y′CbCr matrix.
    enum Colour: Sendable {
        /// Ordinary video (HD, Rec. 709).
        case rec709
        /// HDR as iPhones record it: Rec. 2020 primaries, Hybrid Log-Gamma.
        case hlg
        /// HDR10: Rec. 2020 primaries, Perceptual Quantizer.
        case pq

        var properties: [String: String] {
            switch self {
            case .rec709:
                [
                    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
                ]
            case .hlg:
                [
                    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_2100_HLG,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020,
                ]
            case .pq:
                [
                    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_SMPTE_ST_2084_PQ,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020,
                ]
            }
        }

        /// Kr and Kb of the Y′CbCr matrix.
        var coefficients: (r: Double, b: Double) {
            self == .rec709 ? (0.2126, 0.0722) : (0.2627, 0.0593)
        }
    }

    /// One file of the matrix.
    struct Spec: Sendable {
        var width = 192
        var height = 108
        /// Frames a second; ignored when `frameTimes` is given.
        var frameRate = 30.0
        /// When each frame starts, for a variable frame rate (like a screen recording).
        var frameTimes: [CMTime]? = nil
        var seconds = 1.0
        var codec = AVVideoCodecType.h264
        var colour = Colour.rec709
        /// 10 bits a sample (HEVC Main 10) instead of 8.
        var tenBit = false
        /// Writes Dolby Vision metadata for each frame (profile 8.4, on top of HLG), as iPhones do.
        var dolbyVision = false
        /// Non-linear R′G′B′ of each band (0…1, in `colour`), top to bottom as stored.
        var bands: [(Double, Double, Double)] = [(0.5, 0.5, 0.5)]
        /// The track's orientation, as a phone writes it.
        var transform = CGAffineTransform.identity
        /// Sound: sample rate and channels (a steady tone), or none.
        var audio: (sampleRate: Double, channels: Int)? = nil
        var fileType = AVFileType.mov

        var times: [CMTime] {
            if let frameTimes { return frameTimes }
            let count = Int((seconds * frameRate).rounded())
            // A timescale that holds 29.97 and 23.976 exactly.
            let timescale: CMTimeScale = frameRate.rounded() == frameRate ? CMTimeScale(frameRate) * 100 : 30_000
            let step = Double(timescale) / frameRate
            return (0..<count).map { CMTime(value: CMTimeValue((Double($0) * step).rounded()), timescale: timescale) }
        }

        var duration: CMTime {
            if let frameTimes, let last = frameTimes.last {
                // The last frame lasts as long as the one before it.
                let before = frameTimes.count > 1 ? frameTimes[frameTimes.count - 2] : .zero
                return last + (last - before)
            }
            return CMTime(seconds: seconds, preferredTimescale: 600)
        }
    }

    /// SMPTE ST 2086 for a P3-D65 display of 1000 nits peak, 0.0001 minimum (big-endian, as in HEVC).
    static var displayColorVolume: Data {
        var bytes: [UInt8] = []
        func u16(_ v: Int) { bytes += [UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
        func u32(_ v: Int) { bytes += [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
        // Primaries G, B, R then white point, in units of 0.00002.
        for (x, y) in [(13250, 34500), (7500, 3000), (34000, 16000), (15635, 16450)] { u16(x); u16(y) }
        u32(10_000_000) // max, 0.0001 cd/m²
        u32(1) // min
        return Data(bytes)
    }

    /// MaxCLL 1000, MaxFALL 400.
    static var contentLightLevel: Data { Data([0x03, 0xE8, 0x01, 0x90]) }

    /// The marker band's brightness (luma, 0…1) on frame `index`.
    static func marker(frame index: Int) -> Double {
        0.1 + 0.1 * Double(index % 8)
    }

    /// The frame whose marker is nearest `luma` (0…1), as `index % 8`.
    static func markerFrame(luma: Double) -> Int {
        Int(((luma - 0.1) / 0.1).rounded())
    }

    /// The encoder's settings for `spec`.
    private static func compression(_ spec: Spec) -> [String: Any] {
        var compression: [String: Any] = [AVVideoExpectedSourceFrameRateKey: Int(spec.frameRate.rounded())]
        if spec.codec == .hevc {
            compression[AVVideoProfileLevelKey] = spec.tenBit ? kVTProfileLevel_HEVC_Main10_AutoLevel : kVTProfileLevel_HEVC_Main_AutoLevel
        }
        if spec.colour == .pq {
            // HDR10's static metadata, as cameras write it: a 1000-nit P3 display it was graded on.
            compression[kVTCompressionPropertyKey_MasteringDisplayColorVolume as String] = displayColorVolume
            compression[kVTCompressionPropertyKey_ContentLightLevelInfo as String] = contentLightLevel
        }
        if spec.dolbyVision {
            // Keep the per-frame metadata attached to the pixel buffers.
            compression[kVTCompressionPropertyKey_PreserveDynamicHDRMetadata as String] = true
            compression[kVTCompressionPropertyKey_HDRMetadataInsertionMode as String] = kVTHDRMetadataInsertionMode_Auto
        }
        return compression
    }

    static func write(_ spec: Spec) async throws -> URL {
        let ext = spec.fileType == .mp4 ? "mp4" : "mov"
        let url = FileManager.default.temporaryDirectory.appending(path: "media-\(UUID().uuidString).\(ext)")
        let writer = try AVAssetWriter(outputURL: url, fileType: spec.fileType)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: spec.codec,
                AVVideoWidthKey: spec.width,
                AVVideoHeightKey: spec.height,
                AVVideoColorPropertiesKey: spec.colour.properties,
                AVVideoCompressionPropertiesKey: compression(spec),
            ])
        input.expectsMediaDataInRealTime = false
        input.transform = spec.transform
        let format = spec.tenBit ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: format,
                kCVPixelBufferWidthKey as String: spec.width,
                kCVPixelBufferHeightKey as String: spec.height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            ])
        guard writer.canAdd(input) else { throw WriteError(description: "video input refused") }
        writer.add(input)

        let audioInput = spec.audio.map { audio in
            let made = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: audio.sampleRate, AVNumberOfChannelsKey: audio.channels])
            made.expectsMediaDataInRealTime = false
            writer.add(made)
            return made
        }

        let generator = try spec.dolbyVision ? VTHDRPerFrameMetadataGenerationSession(framesPerSecond: Float(spec.frameRate), hdrFormats: [.dolbyVision]) : nil

        guard writer.startWriting() else { throw writer.error ?? WriteError(description: "startWriting") }
        writer.startSession(atSourceTime: .zero)

        let times = spec.times
        let audioChunks = spec.audio.map { Int((spec.duration.seconds * $0.sampleRate / 1024).rounded(.up)) } ?? 0
        var nextVideo = 0, nextAudio = 0
        if audioChunks == 0 { audioInput?.markAsFinished() }
        while nextVideo < times.count || (audioInput != nil && nextAudio < audioChunks) {
            var progressed = false
            if nextVideo < times.count, input.isReadyForMoreMediaData {
                guard let pool = adaptor.pixelBufferPool else { throw WriteError(description: "no pool") }
                let buffer = try frame(spec, index: nextVideo, pool: pool)
                try generator?.attachMetadata(to: buffer, sceneChange: nextVideo == 0)
                guard adaptor.append(buffer, withPresentationTime: times[nextVideo]) else {
                    throw writer.error ?? WriteError(description: "append video")
                }
                nextVideo += 1
                progressed = true
                if nextVideo == times.count { input.markAsFinished() }
            }
            if let audioInput, let audio = spec.audio, nextAudio < audioChunks, audioInput.isReadyForMoreMediaData {
                guard audioInput.append(try tone(chunk: nextAudio, sampleRate: audio.sampleRate, channels: audio.channels)) else {
                    throw writer.error ?? WriteError(description: "append audio")
                }
                nextAudio += 1
                progressed = true
                if nextAudio == audioChunks { audioInput.markAsFinished() }
            }
            if writer.status == .failed { throw writer.error ?? WriteError(description: "writer failed") }
            if !progressed { try await Task.sleep(for: .milliseconds(1)) }
        }
        // The last frame is shown until the end.
        writer.endSession(atSourceTime: spec.duration)
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? WriteError(description: "finishWriting") }
        return url
    }

    /// One frame: the bands, with the bottom band's left half replaced by the frame marker.
    private static func frame(_ spec: Spec, index: Int, pool: CVPixelBufferPool) throws -> CVPixelBuffer {
        var made: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
        guard let buffer = made else { throw WriteError(description: "no buffer") }
        for (key, value) in spec.colour.properties {
            let attachment: CFString =
                switch key {
                case AVVideoColorPrimariesKey: kCVImageBufferColorPrimariesKey
                case AVVideoTransferFunctionKey: kCVImageBufferTransferFunctionKey
                default: kCVImageBufferYCbCrMatrixKey
                }
            CVBufferSetAttachment(buffer, attachment, value as CFString, .shouldPropagate)
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let (kr, kb) = spec.colour.coefficients
        let kg = 1 - kr - kb
        let bandHeight = max(2, (spec.height / spec.bands.count) & ~1)
        let mark = marker(frame: index)
        // Code values for limited range, at 8 or 10 bits.
        let scale = spec.tenBit ? 4.0 : 1.0
        func codes(_ rgb: (Double, Double, Double)) -> (y: Int, cb: Int, cr: Int) {
            let y = kr * rgb.0 + kg * rgb.1 + kb * rgb.2
            let cb = (rgb.2 - y) / (2 * (1 - kb)), cr = (rgb.0 - y) / (2 * (1 - kr))
            return (
                Int(((16 + 219 * y) * scale).rounded()), Int(((128 + 224 * cb) * scale).rounded()),
                Int(((128 + 224 * cr) * scale).rounded())
            )
        }
        let bandCodes = spec.bands.map(codes)
        let markCodes = codes((mark, mark, mark))
        func value(x: Int, y: Int) -> (y: Int, cb: Int, cr: Int) {
            let band = min(y / bandHeight, spec.bands.count - 1)
            if band == spec.bands.count - 1, x < spec.width / 2 { return markCodes }
            return bandCodes[band]
        }
        let lumaBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)!
        let lumaRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let chromaBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 1)!
        let chromaRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
        // Every row of a band is the same: made once, then copied.
        var lumaRows: [Int: [UInt16]] = [:], chromaRows: [Int: [UInt16]] = [:]
        func lumaLine(_ y: Int) -> [UInt16] {
            let band = min(y / bandHeight, spec.bands.count - 1)
            if let known = lumaRows[band] { return known }
            let line = (0..<spec.width).map { UInt16(value(x: $0, y: y).y) }
            lumaRows[band] = line
            return line
        }
        func chromaLine(_ y: Int) -> [UInt16] {
            let band = min(y / bandHeight, spec.bands.count - 1)
            if let known = chromaRows[band] { return known }
            // Odd sizes have one more chroma sample, covering the last column or row.
            let line = (0..<((spec.width + 1) / 2)).flatMap { x -> [UInt16] in
                let c = value(x: min(x * 2, spec.width - 1), y: y)
                return [UInt16(c.cb), UInt16(c.cr)]
            }
            chromaRows[band] = line
            return line
        }
        for y in 0..<spec.height {
            let line = lumaLine(y)
            let row = lumaBase.advanced(by: y * lumaRow)
            if spec.tenBit {
                line.map { $0 << 6 }.withUnsafeBytes { row.copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
            } else {
                line.map { UInt8($0) }.withUnsafeBytes { row.copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
            }
        }
        for y in 0..<((spec.height + 1) / 2) {
            let line = chromaLine(min(y * 2, spec.height - 1))
            let row = chromaBase.advanced(by: y * chromaRow)
            if spec.tenBit {
                line.map { $0 << 6 }.withUnsafeBytes { row.copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
            } else {
                line.map { UInt8($0) }.withUnsafeBytes { row.copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
            }
        }
        return buffer
    }

    /// 1024 frames of a 440 Hz tone, the same in every channel.
    private static func tone(chunk: Int, sampleRate: Double, channels: Int) throws -> CMSampleBuffer {
        let count = 1024
        let first = chunk * count
        var samples = [Int16](repeating: 0, count: count * channels)
        for i in 0..<count {
            let value = Int16(sin(2 * .pi * 440 * Double(first + i) / sampleRate) * 0.3 * 32_767)
            for c in 0..<channels { samples[i * channels + c] = value }
        }
        var description = AudioStreamBasicDescription(
            mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: UInt32(2 * channels), mFramesPerPacket: 1, mBytesPerFrame: UInt32(2 * channels),
            mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: nil, asbd: &description, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil,
            formatDescriptionOut: &format)
        let bytes = samples.count * 2
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil, customBlockSource: nil, offsetToData: 0,
            dataLength: bytes, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
        guard let format, let block else { throw WriteError(description: "audio buffer") }
        _ = samples.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes) }
        var sample: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: count,
            presentationTimeStamp: CMTime(value: CMTimeValue(first), timescale: CMTimeScale(sampleRate)), packetDescriptions: nil,
            sampleBufferOut: &sample)
        guard let sample else { throw WriteError(description: "audio sample") }
        return sample
    }
}

/// Reading back what was drawn, in a known colour space.
enum ColourPixels {
    /// The RGB of a frame's pixel (origin top left) as 0…255 values in sRGB, whatever the
    /// picture's own colour space: what a colour-managed display shows.
    static func srgb(_ image: CGImage, x: Int, y: Int) -> (r: Double, g: Double, b: Double) {
        read(image, x: x, y: y, space: CGColorSpace(name: CGColorSpace.sRGB)!)
    }

    /// The values as stored (no colour conversion), 0…255.
    static func raw(_ image: CGImage, x: Int, y: Int) -> (r: Double, g: Double, b: Double) {
        read(image, x: x, y: y, space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!)
    }

    private static func read(_ image: CGImage, x: Int, y: Int, space: CGColorSpace) -> (r: Double, g: Double, b: Double) {
        var data = [Float](repeating: 0, count: 4)
        let context = CGContext(
            data: &data, width: 1, height: 1, bitsPerComponent: 32, bytesPerRow: 16, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return (Double(data[0]) * 255, Double(data[1]) * 255, Double(data[2]) * 255)
    }
}
