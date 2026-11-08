@preconcurrency import AVFoundation
import EditorCore

/// Measures the sound of a project, for the pre-export checks (and later, silence removal).
public enum AudioProbe {
    /// The loudest sample (0…1) in `range` of the Short, or nil when it has no sound at all.
    public static func peak(of project: Project, in range: CMTimeRange) async throws -> Float? {
        let composition = try await CompositionBuilder.build(project).composition
        let tracks = try await composition.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { return nil }
        let reader = try AVAssetReader(asset: composition)
        reader.timeRange = range
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? CancellationError() }
        var peak: Float = 0
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            var length = 0
            var pointer: UnsafeMutablePointer<CChar>?
            guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer) == noErr,
                  let pointer else { continue }
            pointer.withMemoryRebound(to: Float.self, capacity: length / 4) { floats in
                for index in 0..<(length / 4) { peak = max(peak, abs(floats[index])) }
            }
        }
        return peak
    }
}

public extension AudioProbe {
    /// How loud the file at `url` is, one value per frame (1/30 s) of its own time, or nil when it
    /// has no sound. Runs off the main actor; a long file takes a moment.
    @concurrent
    static func levels(of url: URL) async throws -> AudioLevels? {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return nil }
        let sampleRate = 48_000
        let window = sampleRate / Int(Project.frameRate)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? CancellationError() }

        var sums: [Double] = []
        var counts: [Int] = []
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            // Place the samples by their time, in case the sound doesn't start at zero.
            let first = Int((CMSampleBufferGetPresentationTimeStamp(sample).seconds * Double(sampleRate)).rounded())
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            var length = 0
            var pointer: UnsafeMutablePointer<CChar>?
            guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer) == noErr,
                  let pointer else { continue }
            pointer.withMemoryRebound(to: Float.self, capacity: length / 4) { floats in
                for index in 0..<(length / 4) {
                    let slot = (first + index) / window
                    guard slot >= 0 else { continue }
                    while sums.count <= slot { sums.append(0); counts.append(0) }
                    sums[slot] += Double(floats[index] * floats[index])
                    counts[slot] += 1
                }
            }
        }
        if reader.status == .failed { throw reader.error ?? CancellationError() }
        return AudioLevels(decibels: zip(sums, counts).map { sum, count in
            guard count > 0, sum > 0 else { return AudioLevels.silence }
            return max(Float(10 * log10(sum / Double(count))), AudioLevels.silence)
        })
    }
}
