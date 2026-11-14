@preconcurrency import AVFoundation
import Accelerate
import EditorCore
import Foundation

/// Listens to a song for its beats: measures how strongly new sounds start over time (spectral
/// flux, with Accelerate), then lets `BeatFinder` find the steady pulse and where bars begin.
/// On this Mac, offline, a second or two for a 3-minute song.
public nonisolated enum BeatDetector {
    static let sampleRate = 22_050.0
    static let windowSize = 1024
    static let hop = 256
    /// The low notes (kick drum, bass) that mark where bars begin.
    static let bassLimit = 150.0

    /// The beats of the sound in the file at `url`, in its own time. Empty when there is no clear pulse.
    @concurrent
    public static func beats(of url: URL) async -> [Beat] {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
            let duration = try? await asset.load(.duration),
            let samples = try? readMono(asset: asset, track: track), samples.count > windowSize
        else { return [] }
        let (onsets, bass) = onsetStrength(samples)
        // A measurement is labelled by where its window starts, but it hears a sound start about
        // half a window and a hop later (checked with clicks): move the beats there.
        let latency = CMTime(seconds: Double(windowSize / 2 + hop) / sampleRate, preferredTimescale: 48_000)
        return BeatFinder.beats(onsets: onsets, bass: bass, rate: sampleRate / Double(hop), length: duration)
            .map { Beat(time: $0.time + latency, isBarStart: $0.isBarStart) }
            .filter { $0.time < duration }
    }

    /// The sound as one channel of floats at `sampleRate`.
    static func readMono(asset: AVAsset, track: AVAssetTrack) throws -> [Float] {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
            ])
        guard reader.canAdd(output) else { return [] }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? CocoaError(.fileReadUnknown) }
        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var chunk = [Float](repeating: 0, count: length / 4)
            chunk.withUnsafeMutableBytes { _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
            samples += chunk
        }
        return samples
    }

    /// For each hop: how much louder the spectrum got (all of it, and just the low notes).
    static func onsetStrength(_ samples: [Float]) -> (onsets: [Float], bass: [Float]) {
        let n = windowSize
        guard let dft = try? vDSP.DiscreteFourierTransform(count: n, direction: .forward, transformType: .complexComplex, ofType: Float.self)
        else { return ([], []) }
        let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: n, isHalfWindow: false)
        let bins = n / 2
        let bassBins = max(2, Int(bassLimit / (sampleRate / Double(n))))
        let zeros = [Float](repeating: 0, count: n)
        var previous = [Float](repeating: 0, count: bins)
        var onsets: [Float] = [], bass: [Float] = []
        onsets.reserveCapacity(samples.count / hop)
        bass.reserveCapacity(samples.count / hop)
        var start = 0
        while start + n <= samples.count {
            let frame = vDSP.multiply(samples[start..<(start + n)], window)
            let (real, imaginary) = dft.transform(real: frame, imaginary: zeros)
            var magnitudes = [Float](repeating: 0, count: bins)
            for i in 0..<bins {
                // Compressed, so quiet details count as well as loud ones.
                magnitudes[i] = log1p(100 * (real[i] * real[i] + imaginary[i] * imaginary[i]).squareRoot())
            }
            var flux: Float = 0, low: Float = 0
            for i in 1..<bins {
                let rise = max(0, magnitudes[i] - previous[i])
                flux += rise
                if i <= bassBins { low += rise }
            }
            onsets.append(flux)
            bass.append(low)
            previous = magnitudes
            start += hop
        }
        // Take away the slowly changing level, so only the starts of sounds stand out.
        return (detrended(onsets), detrended(bass))
    }

    private static func detrended(_ values: [Float]) -> [Float] {
        let radius = 8
        guard values.count > radius * 2 else { return values }
        var result = [Float](repeating: 0, count: values.count)
        var sum: Float = values[0..<min(radius, values.count)].reduce(0, +)
        var count = min(radius, values.count)
        for i in values.indices {
            if i + radius < values.count { sum += values[i + radius]; count += 1 }
            if i - radius - 1 >= 0 { sum -= values[i - radius - 1]; count -= 1 }
            result[i] = max(0, values[i] - sum / Float(count))
        }
        return result
    }
}
