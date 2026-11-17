@preconcurrency import AVFoundation
import EditorCore

/// Measures the sound of a project, for the pre-export checks, loudness and silence removal.
public enum AudioProbe {
    /// Plays the Short's mixed sound (48 kHz stereo floats) through `body`, piece by piece,
    /// starting from `state`. Returns nil when the Short has no sound at all.
    ///
    /// Decoding a whole Short takes seconds, so the reading loop runs on a thread of its own
    /// (`BlockingWork`), never on the main thread or Swift's shared ones; stopping the task stops it.
    private static func readMix<State: Sendable>(
        of built: PlayableComposition, in range: CMTimeRange? = nil, from state: State,
        _ body: @escaping @Sendable (inout State, UnsafeBufferPointer<Float>) -> Void
    ) async throws -> State? {
        let tracks = try await built.composition.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { return nil }
        let reader = try AVAssetReader(asset: built.composition)
        if let range { reader.timeRange = range }
        let output = AVAssetReaderAudioMixOutput(
            audioTracks: tracks,
            audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: LoudnessMeter.sampleRate,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false,
                AVLinearPCMIsBigEndianKey: false,
            ])
        output.audioMix = built.audioMix
        output.audioTimePitchAlgorithm = .spectral
        reader.add(output)
        try Task.checkCancellation()
        guard reader.startReading() else { throw reader.error ?? CancellationError() }
        let reading = Unchecked((reader, output))
        let result = await withTaskCancellationHandler {
            await BlockingWork.run { () -> State in
                let output = reading.value.1
                var state = state
                while let sample = output.copyNextSampleBuffer() {
                    guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
                    var length = 0
                    var pointer: UnsafeMutablePointer<CChar>?
                    guard
                        CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer) == noErr,
                        let pointer
                    else { continue }
                    pointer.withMemoryRebound(to: Float.self, capacity: length / 4) { floats in
                        body(&state, UnsafeBufferPointer(start: floats, count: length / 4))
                    }
                }
                return state
            }
        } onCancel: {
            reading.value.0.cancelReading()
        }
        try Task.checkCancellation()
        switch reader.status {
        case .failed: throw reader.error ?? CancellationError()
        case .cancelled: throw CancellationError()
        default: return result
        }
    }

    /// The loudest sample (0…1) in `range` of the Short, or nil when it has no sound at all.
    public static func peak(of project: Project, in range: CMTimeRange, analysis: MediaAnalysis = MediaAnalysis()) async throws -> Float? {
        try await readMix(of: CompositionBuilder.build(project, analysis: analysis), in: range, from: Float(0)) { peak, samples in
            for x in samples { peak = max(peak, abs(x)) }
        }
    }

    /// The loudness of the whole Short as mixed (clip volumes, music), or nil when it has no sound.
    public static func loudness(of project: Project, analysis: MediaAnalysis = MediaAnalysis()) async throws -> LoudnessMeter? {
        try await readMix(of: CompositionBuilder.build(project, analysis: analysis), from: LoudnessMeter()) { meter, samples in
            meter.add(interleaved: samples)
        }
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
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
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

        // Decoding blocks its thread: on one of its own (BlockingWork), never a shared one.
        let reading = Unchecked(output)
        let (sums, counts) = try await BlockingWork.run { stop -> ([Double], [Int]) in
            let output = reading.value
            var sums: [Double] = []
            var counts: [Int] = []
            while let sample = output.copyNextSampleBuffer() {
                try stop.check()
                // Place the samples by their time, in case the sound doesn't start at zero.
                let first = Int((CMSampleBufferGetPresentationTimeStamp(sample).seconds * Double(sampleRate)).rounded())
                guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
                var length = 0
                var pointer: UnsafeMutablePointer<CChar>?
                guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer) == noErr,
                    let pointer
                else { continue }
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
            return (sums, counts)
        }
        if reader.status == .failed { throw reader.error ?? CancellationError() }
        return AudioLevels(
            decibels: zip(sums, counts).map { sum, count in
                guard count > 0, sum > 0 else { return AudioLevels.silence }
                return max(Float(10 * log10(sum / Double(count))), AudioLevels.silence)
            })
    }
}
