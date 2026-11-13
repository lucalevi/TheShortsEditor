@preconcurrency import AVFoundation
import CoreImage
import CryptoKit
import EditorCore
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Remove Background (Stage K): makes a copy of a video or picture in which only the people (or
/// the main subject) are left and everything else is see-through. Vision finds them on each
/// frame, on this Mac. A video copy is HEVC with transparency, with the same frame times as the
/// original, so a clip plays it in place of its file; a picture copy is a PNG.
public nonisolated enum CutoutMaker {
    public enum CutoutError: LocalizedError {
        case unreadable
        case failed

        public var errorDescription: String? {
            switch self {
            case .unreadable: "The file's picture couldn't be read."
            case .failed: "The see-through copy couldn't be written."
            }
        }
    }

    /// Copies are made at most this big (long side): enough for a 1080×1920 Short.
    static let maxSide: CGFloat = 1920

    /// Makes the see-through copy of the video at `url` into `destination`. `matte` (for tests)
    /// replaces Vision: it gets each upright frame and gives a grey picture, white where it is kept.
    @concurrent
    public static func makeVideo(from url: URL, to destination: URL, subject: CutoutSubject,
                                 matte: (@Sendable (CIImage) -> CIImage?)? = nil,
                                 progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw CutoutError.unreadable }
        let (naturalSize, transform, range) = try await track.load(.naturalSize, .preferredTransform, .timeRange)
        guard naturalSize.width > 0, naturalSize.height > 0 else { throw CutoutError.unreadable }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)

        let scale = min(1, maxSide / max(naturalSize.width, naturalSize.height))
        let width = max(2, Int((naturalSize.width * scale / 2).rounded()) * 2), height = max(2, Int((naturalSize.height * scale / 2).rounded()) * 2)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let partial = destination.deletingPathExtension().appendingPathExtension("partial.mov")
        try? FileManager.default.removeItem(at: partial)
        let writer = try AVAssetWriter(outputURL: partial, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevcWithAlpha,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoQualityKey: 0.8] as [String: Any],
        ])
        input.expectsMediaDataInRealTime = false
        // The same turn; its move is in pixels of the smaller copy.
        input.transform = CGAffineTransform(a: transform.a, b: transform.b, c: transform.c, d: transform.d,
                                            tx: transform.tx * CGFloat(width) / naturalSize.width, ty: transform.ty * CGFloat(height) / naturalSize.height)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        guard writer.canAdd(input) else { throw CutoutError.failed }
        writer.add(input)
        guard reader.startReading() else { throw reader.error ?? CutoutError.unreadable }
        guard writer.startWriting() else { throw writer.error ?? CutoutError.failed }

        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull(), .cacheIntermediates: false])
        let finder = MatteFinder(subject: subject, forVideo: true)
        let small = CGAffineTransform(scaleX: CGFloat(width) / naturalSize.width, y: CGFloat(height) / naturalSize.height)
        let stored = CGRect(x: 0, y: 0, width: width, height: height)
        let upright = Self.uprightTransform(transform, storedSize: stored.size)
        var previous: CIImage?
        var started = false
        let total = max(range.duration.seconds, 0.001)
        var count = 0
        do {
            while let sample = output.copyNextSampleBuffer() {
                try Task.checkCancellation()
                guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
                let time = CMSampleBufferGetPresentationTimeStamp(sample)
                let frame = CIImage(cvPixelBuffer: buffer).transformed(by: small).cropped(to: stored)
                let straight = frame.transformed(by: upright)
                var kept = (matte?(straight) ?? finder.matte(of: straight)) ?? CIImage(color: .black).cropped(to: straight.extent)
                // A little of the frame before, so edges don't flicker from frame to frame.
                if let before = previous {
                    kept = before.applyingFilter("CIDissolveTransition", parameters: ["inputTargetImage": kept, "inputTime": 0.7])
                        .cropped(to: straight.extent)
                }
                previous = kept
                let mask = kept.transformed(by: upright.inverted()).cropped(to: stored)
                let cut = CutoutRenderer.masked(frame, by: mask)
                if !started {
                    writer.startSession(atSourceTime: time)
                    started = true
                }
                while !input.isReadyForMoreMediaData {
                    if writer.status == .failed { throw writer.error ?? CutoutError.failed }
                    try await Task.sleep(for: .milliseconds(2))
                }
                guard let pool = adaptor.pixelBufferPool else { throw writer.error ?? CutoutError.failed }
                var made: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &made)
                guard let made else { throw CutoutError.failed }
                context.render(cut, to: made, bounds: stored, colorSpace: nil)
                guard adaptor.append(made, withPresentationTime: time) else { throw writer.error ?? CutoutError.failed }
                count += 1
                if count.isMultiple(of: 10) { progress(min((time - range.start).seconds / total, 0.99)) }
            }
            if reader.status == .failed { throw reader.error ?? CutoutError.unreadable }
            guard started else { throw CutoutError.unreadable }
            input.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? CutoutError.failed }
            try FileManager.default.moveItem(at: partial, to: destination)
        } catch {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
        progress(1)
    }

    /// Makes the see-through copy of the picture at `url` (a PNG) into `destination`.
    @concurrent
    public static func makePicture(from url: URL, to destination: URL, subject: CutoutSubject,
                                   matte: (@Sendable (CIImage) -> CIImage?)? = nil) async throws {
        guard let picture = StillImages.image(at: url) else { throw CutoutError.unreadable }
        let image = CIImage(cgImage: picture)
        let kept = (matte?(image) ?? MatteFinder(subject: subject, forVideo: false).matte(of: image)) ?? CIImage(color: .black).cropped(to: image.extent)
        let cut = CutoutRenderer.masked(image, by: kept)
        let context = CIContext(options: [.workingColorSpace: NSNull(), .cacheIntermediates: false])
        guard let cg = context.createCGImage(cut, from: image.extent, format: .RGBA8, colorSpace: picture.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)) else {
            throw CutoutError.failed
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let file = CGImageDestinationCreateWithURL(destination as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw CutoutError.failed }
        CGImageDestinationAddImage(file, cg, nil)
        guard CGImageDestinationFinalize(file) else { throw CutoutError.failed }
    }

    /// Takes a stored frame (Core Image's coordinates, origin at the bottom left) to its upright
    /// picture, with the origin at 0, 0. `transform` is the track's, in top-left coordinates.
    static func uprightTransform(_ transform: CGAffineTransform, storedSize: CGSize) -> CGAffineTransform {
        let rect = CGRect(origin: .zero, size: storedSize).applying(transform)
        let topLeft = transform.concatenating(CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
        return CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: storedSize.height)
            .concatenating(topLeft)
            .concatenating(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: rect.height))
    }
}

/// Finds what to keep in a picture with Vision: a grey picture the same size, white where kept.
private nonisolated final class MatteFinder {
    let subject: CutoutSubject
    private let people = VNGeneratePersonSegmentationRequest()
    private let lifting = VNGenerateForegroundInstanceMaskRequest()

    init(subject: CutoutSubject, forVideo: Bool) {
        self.subject = subject
        // The careful one on every frame: it is made once, so quality matters more than speed.
        people.qualityLevel = .accurate
        people.outputPixelFormat = kCVPixelFormatType_OneComponent8
    }

    func matte(of image: CIImage) -> CIImage? {
        let extent = image.extent
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        let mask: CVPixelBuffer?
        switch subject {
        case .people:
            guard (try? handler.perform([people])) != nil else { return nil }
            mask = people.results?.first?.pixelBuffer
        case .subject:
            guard (try? handler.perform([lifting])) != nil, let found = lifting.results?.first else { return nil }
            mask = try? found.generateScaledMaskForImage(forInstances: found.allInstances, from: handler)
        }
        guard let mask else { return nil }
        let grey = CIImage(cvPixelBuffer: mask)
        let sx = extent.width / grey.extent.width, sy = extent.height / grey.extent.height
        return grey.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            .applyingFilter("CIMaximumComponent")
            .cropped(to: extent)
    }
}

/// See-through copies made by Remove Background, kept in Caches (named after the file's path,
/// size and date, so a changed file is made again).
public enum CutoutCache {
    static var folder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "Shorts Editor/Cut-outs", directoryHint: .isDirectory)
    }

    /// Where the copy of the file at `url` keeping `subject` goes.
    public static func copyURL(for url: URL, subject: CutoutSubject, isImage: Bool) -> URL {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let key = "\(url.path)|\(values?.fileSize ?? 0)|\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        let digest = SHA256.hash(data: Data(key.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return folder.appending(path: "\(digest)-\(subject.rawValue).\(isImage ? "png" : "mov")")
    }

    /// The copy, if it has been made.
    public static func existingCopy(of url: URL, subject: CutoutSubject, isImage: Bool) -> URL? {
        let copy = copyURL(for: url, subject: subject, isImage: isImage)
        return FileManager.default.fileExists(atPath: copy.path) ? copy : nil
    }

    /// The file a clip's picture is read from: its see-through copy when it removes its background
    /// and the copy has been made, else its own file.
    public static func pictureURL(for clip: Clip, media: MediaAsset) -> URL {
        guard let subject = clip.cutout.removeBackground,
              let copy = existingCopy(of: media.url, subject: subject, isImage: media.isImage) else { return media.url }
        return copy
    }

    /// Makes the copy unless that was done already.
    public static func make(_ url: URL, subject: CutoutSubject, isImage: Bool,
                            progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        if let copy = existingCopy(of: url, subject: subject, isImage: isImage) { return copy }
        let copy = copyURL(for: url, subject: subject, isImage: isImage)
        if isImage {
            try await CutoutMaker.makePicture(from: url, to: copy, subject: subject)
        } else {
            try await CutoutMaker.makeVideo(from: url, to: copy, subject: subject, progress: progress)
        }
        return copy
    }
}
