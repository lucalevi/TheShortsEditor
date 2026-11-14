@preconcurrency import AVFoundation
import CoreImage
import CryptoKit
import EditorCore
import Vision

/// Measures camera shake for Stabilize: how far the picture moves from each frame to the next
/// (Vision's image registration on small copies of the frames), added up into a `ShakePath`.
public nonisolated enum Stabilizer {
    public enum AnalysisError: LocalizedError {
        case noPicture

        public var errorDescription: String? { "This file has no moving picture to steady." }
    }

    /// Frames are compared at this width (long side), which is quick and precise enough.
    static let analysisSide: CGFloat = 320

    /// Reads every frame of the video at `url` (at most 30 a second) and measures how its picture
    /// moves. `progress` gets 0…1 now and then. Runs off the main actor.
    @concurrent
    public static func analyse(_ url: URL, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> ShakePath {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw AnalysisError.noPicture }
        let (range, naturalSize) = try await track.load(.timeRange, .naturalSize)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? AnalysisError.noPicture }

        let scale = analysisSide / max(naturalSize.width, naturalSize.height, 1)
        let small = CGSize(width: naturalSize.width * scale, height: naturalSize.height * scale)
        let context = CIContext(options: [.workingColorSpace: NSNull(), .cacheIntermediates: false])
        let minimumGap = 1.0 / Double(Project.frameRate) - 0.002

        var positions: [CGPoint] = []
        var times: [Double] = []
        var previous: CGImage?
        var position = CGPoint.zero
        let total = max(range.duration.seconds, 0.001)
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            // High frame rates (slow-motion footage) are read at 30 a second.
            if let last = times.last, time - last < minimumGap { continue }
            let image = CIImage(cvPixelBuffer: buffer).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            guard let current = context.createCGImage(image, from: CGRect(origin: .zero, size: small)) else { continue }
            if let previous {
                let request = VNTranslationalImageRegistrationRequest(targetedCGImage: current)
                try VNImageRequestHandler(cgImage: previous).perform([request])
                if let alignment = request.results?.first?.alignmentTransform {
                    // The shift that lines this frame up with the one before is how far its
                    // content moved, the other way round. Vision's y goes up, the path's goes
                    // down, so y keeps its sign.
                    position.x -= alignment.tx / small.width
                    position.y += alignment.ty / small.height
                }
            }
            positions.append(position)
            times.append(time)
            previous = current
            if positions.count.isMultiple(of: 15) { progress(min((time - range.start.seconds) / total, 1)) }
        }
        if reader.status == .failed { throw reader.error ?? AnalysisError.noPicture }
        guard let first = times.first, let last = times.last, positions.count > 1 else {
            return ShakePath(interval: 1.0 / Double(Project.frameRate), start: times.first ?? 0, positions: positions)
        }
        progress(1)
        return ShakePath(interval: (last - first) / Double(positions.count - 1), start: first, positions: positions)
    }
}

/// Measured shake paths, kept in memory and in Caches (named after the file's path, size and
/// date, so a changed file is measured again).
public enum ShakeCache {
    private static var known: [URL: ShakePath] = [:]

    static var folder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "Shorts Editor/Steady", directoryHint: .isDirectory)
    }

    static func fileURL(for url: URL) -> URL {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let key = "\(url.path)|\(values?.fileSize ?? 0)|\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        let digest = SHA256.hash(data: Data(key.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return folder.appending(path: "\(digest).json")
    }

    /// The path of the file at `url`, if it has been measured.
    public static func path(for url: URL) -> ShakePath? {
        if let path = known[url] { return path }
        guard let data = try? Data(contentsOf: fileURL(for: url)),
            let path = try? JSONDecoder().decode(ShakePath.self, from: data)
        else { return nil }
        known[url] = path
        return path
    }

    /// Measures the file at `url` unless that was done already.
    public static func measure(_ url: URL, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> ShakePath {
        if let path = path(for: url) { return path }
        let path = try await Stabilizer.analyse(url, progress: progress)
        known[url] = path
        Log.render.attempt("Keeping a measured shake path") {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONEncoder().encode(path).write(to: fileURL(for: url), options: .atomic)
        }
        return path
    }
}
