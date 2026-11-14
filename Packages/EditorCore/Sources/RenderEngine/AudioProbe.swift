@preconcurrency import AVFoundation
import EditorCore

/// Measures the sound of a project, for the pre-export checks, loudness and silence removal.
public enum AudioProbe {
    /// Plays the Short's mixed sound (48 kHz stereo floats) through `body`, piece by piece.
    /// Returns false when the Short has no sound at all.
    private static func readMix(of built: PlayableComposition, in range: CMTimeRange? = nil, _ body: (UnsafeBufferPointer<Float>) -> Void) async throws -> Bool
    {
        let tracks = try await built.composition.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { return false }
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
        guard reader.startReading() else { throw reader.error ?? CancellationError() }
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            var length = 0
            var pointer: UnsafeMutablePointer<CChar>?
            guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer) == noErr,
                let pointer
            else { continue }
            pointer.withMemoryRebound(to: Float.self, capacity: length / 4) { floats in
                body(UnsafeBufferPointer(start: floats, count: length / 4))
            }
        }
        if reader.status == .failed { throw reader.error ?? CancellationError() }
        return true
    }

    /// The loudest sample (0…1) in `range` of the Short, or nil when it has no sound at all.
    public static func peak(of project: Project, in range: CMTimeRange) async throws -> Float? {
        var peak: Float = 0
        let hasSound = try await readMix(of: CompositionBuilder.build(project), in: range) { samples in
            for x in samples { peak = max(peak, abs(x)) }
        }
        return hasSound ? peak : nil
    }

    /// The loudness of the whole Short as mixed (clip volumes, music), or nil when it has no sound.
    public static func loudness(of project: Project) async throws -> LoudnessMeter? {
        var meter = LoudnessMeter()
        let hasSound = try await readMix(of: CompositionBuilder.build(project)) { meter.add(interleaved: $0) }
        return hasSound ? meter : nil
    }
}

/// Sound levels of files, measured once each and shared by everything that needs them
/// (lowering music under speech, removing pauses).
@MainActor
public enum LevelCache {
    private static var measured: [URL: AudioLevels?] = [:]
    private static var running: [URL: Task<AudioLevels?, Never>] = [:]

    /// The file's levels, measuring them the first time. Nil when it has no sound or can't be read.
    public static func levels(of url: URL) async -> AudioLevels? {
        if let known = measured[url] { return known }
        if let task = running[url] { return await task.value }
        let task = Task { try? await AudioProbe.levels(of: url) }
        running[url] = task
        let result = await task.value
        running[url] = nil
        measured[url] = result
        return result
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
        if reader.status == .failed { throw reader.error ?? CancellationError() }
        return AudioLevels(
            decibels: zip(sums, counts).map { sum, count in
                guard count > 0, sum > 0 else { return AudioLevels.silence }
                return max(Float(10 * log10(sum / Double(count))), AudioLevels.silence)
            })
    }
}
