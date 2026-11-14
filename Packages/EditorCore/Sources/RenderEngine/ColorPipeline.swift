@preconcurrency import AVFoundation
import CoreImage
import EditorCore
import Synchronization
import VideoToolbox

/// The range of brightness a Short is made for.
public nonisolated enum DynamicRange: String, Sendable, CaseIterable {
    /// Ordinary video (Rec. 709): what every screen shows. Preview, thumbnails and the usual export.
    case standard
    /// HDR (Rec. 2020, Hybrid Log-Gamma, 10 bits), as iPhones record it. Bright parts stay bright
    /// on HDR screens; other screens show it like ordinary video.
    case high
}

/// How colour is handled from the files to the finished Short, in one place.
///
/// - **Sources** reach the compositor as they are in the file (its `supportsHDRSourceFrames` is
///   always true), whichever way the frames are asked for. For a standard Short, HDR frames (HLG,
///   PQ, Dolby Vision) are turned into Rec. 709 by `HDRConversion` with VideoToolbox's tone
///   mapping, the one AVFoundation and Apple's apps use. (Left to AVFoundation, the player and
///   thumbnails passed PQ frames through unconverted while export converted them, measured
///   2026-11-14.) Every frame carries its colour space, so Core Image knows it.
/// - **Core Image works in extended sRGB** (non-linear, values may go past 0…1). Every picture is
///   converted into it on the way in: video (Rec. 709 or HDR), photos (sRGB, Display P3), titles,
///   captions and stickers (drawn in sRGB). The looks, effects, blurs and blends were made on
///   non-linear values and keep working on them, so a Short looks the same as before, but now
///   pictures of different colour spaces meet correctly. Intermediate results are 16-bit float.
/// - **Output** is tagged and converted to the Short's colour space (`Output`), which the video
///   composition, the compositor's frames and the exported file all share.
///
/// Our own colour maths (looks, Enhance, Match Color, colour pop, green screen) is defined on sRGB
/// values: frames are measured in sRGB (`LookRenderer.pixels`) and the lookup tables are applied in
/// sRGB (`CIColorCubeWithColorSpace`), so a measured colour and a drawn one are the same.
public nonisolated enum ColorPipeline {
    /// Where Core Image does its work.
    static let workingSpace = CGColorSpace(name: CGColorSpace.extendedSRGB)!
    /// Titles, captions, stickers, colour pickers and our colour maths.
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// The colour space of a Short's frames.
    public struct Output: Sendable {
        public let primaries: String
        public let transferFunction: String
        public let matrix: String

        /// For `AVVideoColorPropertiesKey`.
        public var properties: [String: String] {
            [
                AVVideoColorPrimariesKey: primaries,
                AVVideoTransferFunctionKey: transferFunction,
                AVVideoYCbCrMatrixKey: matrix,
            ]
        }

        /// The attachments a pixel buffer of this space carries.
        var attachments: [CFString: CFString] {
            [
                kCVImageBufferColorPrimariesKey: primaries as CFString,
                kCVImageBufferTransferFunctionKey: transferFunction as CFString,
                kCVImageBufferYCbCrMatrixKey: matrix as CFString,
            ]
        }

        /// The colour space Core Image reads such a buffer in, made from the same attachments so
        /// that video passes through unchanged when nothing is drawn over it.
        let space: CGColorSpace

        init(primaries: String, transferFunction: String, matrix: String, fallback: CFString) {
            self.primaries = primaries
            self.transferFunction = transferFunction
            self.matrix = matrix
            let attachments = [
                kCVImageBufferColorPrimariesKey: primaries, kCVImageBufferTransferFunctionKey: transferFunction,
                kCVImageBufferYCbCrMatrixKey: matrix,
            ]
            space =
                CVImageBufferCreateColorSpaceFromAttachments(attachments as CFDictionary)?.takeRetainedValue()
                ?? CGColorSpace(name: fallback)!
        }
    }

    private static let standard = Output(
        primaries: AVVideoColorPrimaries_ITU_R_709_2, transferFunction: AVVideoTransferFunction_ITU_R_709_2,
        matrix: AVVideoYCbCrMatrix_ITU_R_709_2, fallback: CGColorSpace.itur_709)
    private static let high = Output(
        primaries: AVVideoColorPrimaries_ITU_R_2020, transferFunction: AVVideoTransferFunction_ITU_R_2100_HLG,
        matrix: AVVideoYCbCrMatrix_ITU_R_2020, fallback: CGColorSpace.itur_2100_HLG)

    public static func output(_ range: DynamicRange) -> Output {
        range == .high ? high : standard
    }

    /// A Core Image context for drawing frames: the working space above, 16-bit float.
    static func makeContext() -> CIContext {
        CIContext(options: [
            .workingColorSpace: workingSpace,
            .workingFormat: CIFormat.RGBAh,
            .cacheIntermediates: false,
        ])
    }

    /// Says what colour space `buffer` holds (Core Image and the encoder read it).
    static func tag(_ buffer: CVPixelBuffer, as output: Output) {
        CVBufferSetAttachments(buffer, output.attachments as CFDictionary, .shouldPropagate)
    }

    /// A colour picked in the app (sRGB values), for Core Image.
    static func color(red: Double, green: Double, blue: Double, alpha: Double = 1) -> CIColor {
        CIColor(red: red, green: green, blue: blue, alpha: alpha, colorSpace: sRGB) ?? CIColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// Whether a video file holds HDR (HLG, PQ / HDR10, or Dolby Vision on top of either).
    public static func isHDR(_ url: URL) async -> Bool {
        let tracks = try? await AVURLAsset(url: url).loadTracks(withMediaCharacteristic: .containsHDRVideo)
        return tracks?.isEmpty == false
    }

    /// How a copy the app makes of a video (backwards, smooth slow motion, cut out) keeps the
    /// source's colours: the same colour space, and 10 bits when the source has them.
    struct CopyColor {
        /// For `AVVideoColorPropertiesKey`; nil when the file doesn't say.
        let properties: [String: String]?
        let tenBit: Bool

        /// Bytes a decoded 4:2:0 picture takes per pixel.
        var bytesPerPixel: Double { tenBit ? 3 : 1.5 }

        /// Writer settings for the copy: 10-bit HEVC for 10-bit or HDR video, else H.264 (or
        /// `codec`), with `compression`, tagged with the source's colour space.
        func writerSettings(width: Int, height: Int, codec: AVVideoCodecType? = nil, compression: [String: Any]) -> [String: Any] {
            var compression = compression
            if codec == nil {
                compression[AVVideoProfileLevelKey] = tenBit ? kVTProfileLevel_HEVC_Main10_AutoLevel as String : AVVideoProfileLevelH264HighAutoLevel
            }
            var settings: [String: Any] = [
                AVVideoCodecKey: codec ?? (tenBit ? .hevc : .h264), AVVideoWidthKey: width, AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: compression,
            ]
            settings[AVVideoColorPropertiesKey] = properties
            return settings
        }

        /// Says that a picture of the copy holds the source's colours, so the encoder doesn't take
        /// an untagged picture for Rec. 709 and convert it.
        func tag(_ buffer: CVPixelBuffer) {
            guard let properties else { return }
            let keys: [String: CFString] = [
                AVVideoColorPrimariesKey: kCVImageBufferColorPrimariesKey,
                AVVideoTransferFunctionKey: kCVImageBufferTransferFunctionKey,
                AVVideoYCbCrMatrixKey: kCVImageBufferYCbCrMatrixKey,
            ]
            for (key, value) in properties {
                if let attachment = keys[key] { CVBufferSetAttachment(buffer, attachment, value as CFString, .shouldPropagate) }
            }
        }
    }

    static func copyColor(of track: AVAssetTrack) async -> CopyColor {
        guard let description = try? await track.load(.formatDescriptions).first else { return CopyColor(properties: nil, tenBit: false) }
        let extensions = CMFormatDescriptionGetExtensions(description) as? [CFString: Any] ?? [:]
        let depth = (extensions[kCMFormatDescriptionExtension_BitsPerComponent] as? Int) ?? 8
        let hdr = await (try? track.load(.mediaCharacteristics).contains(.containsHDRVideo)) ?? false
        guard let primaries = extensions[kCMFormatDescriptionExtension_ColorPrimaries] as? String,
            let transfer = extensions[kCMFormatDescriptionExtension_TransferFunction] as? String,
            let matrix = extensions[kCMFormatDescriptionExtension_YCbCrMatrix] as? String
        else { return CopyColor(properties: nil, tenBit: depth > 8 || hdr) }
        return CopyColor(
            properties: [AVVideoColorPrimariesKey: primaries, AVVideoTransferFunctionKey: transfer, AVVideoYCbCrMatrixKey: matrix],
            tenBit: depth > 8 || hdr)
    }

    /// Whether a frame holds HDR values (HLG or PQ; Dolby Vision is carried on top of one of them).
    static func isHDR(_ buffer: CVPixelBuffer) -> Bool {
        guard let transfer = CVBufferCopyAttachment(buffer, kCVImageBufferTransferFunctionKey, nil) as? String else { return false }
        return transfer == (kCVImageBufferTransferFunction_ITU_R_2100_HLG as String)
            || transfer == (kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String)
    }
}

/// Turns HDR frames into ordinary (Rec. 709) ones with VideoToolbox's tone mapping, the same one
/// AVFoundation uses, so an HDR clip looks the same in a standard Short however its frames are
/// read. Thread-safe: the compositor calls it from AVFoundation's queues.
nonisolated final class HDRConversion: Sendable {
    private struct State: @unchecked Sendable {
        var session: VTPixelTransferSession?
        var pools: [String: CVPixelBufferPool] = [:]
    }

    private let state = Mutex(State())

    /// `buffer` itself when it isn't HDR, else a Rec. 709 copy (10 bits, so nothing is lost
    /// before Core Image reads it). Nil only when the conversion fails.
    func standard(_ buffer: CVPixelBuffer) -> CVPixelBuffer? {
        guard ColorPipeline.isHDR(buffer) else { return buffer }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        // Keep see-through pictures see-through.
        let hasAlpha =
            CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA
            || CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_64RGBAHalf
        let format = hasAlpha ? kCVPixelFormatType_64RGBAHalf : kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
        // (Boxed: a pixel buffer isn't Sendable, and it leaves the lock.)
        struct Made: @unchecked Sendable { let buffer: CVPixelBuffer? }
        return state.withLock { state -> Made in
            if state.session == nil {
                var session: VTPixelTransferSession?
                VTPixelTransferSessionCreate(allocator: nil, pixelTransferSessionOut: &session)
                guard let session else { return Made(buffer: nil) }
                let output = ColorPipeline.output(.standard)
                VTSessionSetProperty(session, key: kVTPixelTransferPropertyKey_DestinationColorPrimaries, value: output.primaries as CFString)
                VTSessionSetProperty(session, key: kVTPixelTransferPropertyKey_DestinationTransferFunction, value: output.transferFunction as CFString)
                VTSessionSetProperty(session, key: kVTPixelTransferPropertyKey_DestinationYCbCrMatrix, value: output.matrix as CFString)
                state.session = session
            }
            guard let session = state.session else { return Made(buffer: nil) }
            let key = "\(width)x\(height)|\(format)"
            if state.pools[key] == nil {
                var pool: CVPixelBufferPool?
                CVPixelBufferPoolCreate(
                    nil, nil,
                    [
                        kCVPixelBufferPixelFormatTypeKey: format, kCVPixelBufferWidthKey: width, kCVPixelBufferHeightKey: height,
                        kCVPixelBufferIOSurfacePropertiesKey: [String: Any](),
                    ] as CFDictionary, &pool)
                // A few sizes at most are in use at once.
                if state.pools.count > 8 { state.pools.removeAll() }
                state.pools[key] = pool
            }
            guard let pool = state.pools[key] else { return Made(buffer: nil) }
            var made: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
            guard let made, VTPixelTransferSessionTransferImage(session, from: buffer, to: made) == noErr else { return Made(buffer: nil) }
            return Made(buffer: made)
        }.buffer
    }
}
