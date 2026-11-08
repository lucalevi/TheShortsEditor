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
