@preconcurrency import AVFoundation
import CoreVideo

/// A one-second black video, stretched over clips whose file is missing. An empty stretch of a
/// track would do inside the Short, but at its end it wouldn't count towards its length.
@MainActor
enum Placeholder {
    private static var cached: AVURLAsset?

    static func blackVideoTrack() async throws -> (asset: AVURLAsset, track: AVAssetTrack) {
        if let cached, let track = try await cached.loadTracks(withMediaType: .video).first { return (cached, track) }
        let url = FileManager.default.temporaryDirectory.appending(path: "shorts-editor-missing-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CancellationError() }
        writer.startSession(atSourceTime: .zero)

        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA, nil, &buffer)
        guard let buffer else { throw CancellationError() }
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer), 0, CVPixelBufferGetDataSize(buffer))
        for y in 0..<64 {  // opaque black (alpha 255)
            let row = CVPixelBufferGetBaseAddress(buffer)!.advanced(by: y * CVPixelBufferGetBytesPerRow(buffer)).assumingMemoryBound(to: UInt8.self)
            for x in 0..<64 { row[x * 4 + 3] = 255 }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        for frame in 0..<30 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(1)) }
            adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 30))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: 1, timescale: 1))
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CancellationError() }
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw CancellationError() }
        cached = asset
        return (asset, track)
    }
}
