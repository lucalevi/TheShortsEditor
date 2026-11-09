@preconcurrency import AVFoundation
import AudioToolbox
import CryptoKit
import Foundation

/// Cleans up a recording's sound with Apple's voice isolation (the same as FaceTime's "Voice
/// Isolation"): background noise and hum go, the voice stays. Runs on the Mac, offline, once per
/// file; the result is kept in the app's caches and used instead of the file's own sound.
public nonisolated enum VoiceCleaner {
    public enum CleanError: LocalizedError {
        case unavailable
        case failed

        public var errorDescription: String? {
            switch self {
            case .unavailable: "Voice clean-up isn't available on this Mac."
            case .failed: "The sound couldn't be cleaned up."
            }
        }
    }

    static var folder: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appending(path: "Shorts Editor/Clean Voice", directoryHint: .isDirectory)
    }

    /// Where the cleaned sound of `url` is kept: named after the file's path, size and date, so a
    /// changed file is cleaned again.
    public static func cleanedURL(for url: URL) -> URL {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let key = "\(url.path)|\(values?.fileSize ?? 0)|\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        let digest = SHA256.hash(data: Data(key.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return folder.appending(path: "\(digest).m4a")
    }

    /// The cleaned sound of `url`, when it has been made.
    public static func existingCleanedURL(for url: URL) -> URL? {
        let cleaned = cleanedURL(for: url)
        return FileManager.default.fileExists(atPath: cleaned.path) ? cleaned : nil
    }

    static var description: AudioComponentDescription {
        AudioComponentDescription(componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_AUSoundIsolation,
                                  componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
    }

    public static var isAvailable: Bool {
        var description = description
        return AudioComponentFindNext(nil, &description) != nil
    }

    /// Makes the cleaned sound of `url` (or returns it if it exists), reporting progress 0…1.
    @concurrent
    public static func clean(_ url: URL, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        if let existing = existingCleanedURL(for: url) { return existing }
        guard isAvailable else { throw CleanError.unavailable }
        let destination = cleanedURL(for: url)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let input = try AVAudioFile(forReading: url)
        let format = input.processingFormat
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let effect = AVAudioUnitEffect(audioComponentDescription: description)
        engine.attach(player)
        engine.attach(effect)
        engine.connect(player, to: effect, format: format)
        engine.connect(effect, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        if let wetDry = effect.auAudioUnit.parameterTree?.parameter(withAddress: AUParameterAddress(kAUSoundIsolationParam_WetDryMixPercent)) {
            wetDry.value = 100
        }
        try engine.start()
        player.scheduleFile(input, at: nil, completionHandler: nil)
        player.play()

        // The unit runs a little late: skip that much at the start and render that much more at the end.
        let latency = AVAudioFramePosition((effect.auAudioUnit.latency * format.sampleRate).rounded())
        let total = input.length
        let temporary = destination.deletingLastPathComponent().appending(path: UUID().uuidString + ".m4a")
        let output = try AVAudioFile(forWriting: temporary, settings: [
            AVFormatIDKey: kAudioFormatAppleLossless,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderBitDepthHintKey: 24,
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: engine.manualRenderingMaximumFrameCount) else {
            throw CleanError.failed
        }
        var rendered: AVAudioFramePosition = 0
        var written: AVAudioFramePosition = 0
        while written < total {
            try Task.checkCancellation()
            let frames = AVAudioFrameCount(min(AVAudioFramePosition(buffer.frameCapacity), total + latency - rendered))
            guard frames > 0 else { break }
            let status = try engine.renderOffline(frames, to: buffer)
            guard status == .success else { throw CleanError.failed }
            var start = AVAudioFramePosition(0)
            if rendered < latency { start = min(latency - rendered, AVAudioFramePosition(buffer.frameLength)) }
            rendered += AVAudioFramePosition(buffer.frameLength)
            let keep = min(AVAudioFramePosition(buffer.frameLength) - start, total - written)
            if keep > 0 {
                if start > 0 || keep < AVAudioFramePosition(buffer.frameLength) {
                    guard let part = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(keep)) else { throw CleanError.failed }
                    part.frameLength = AVAudioFrameCount(keep)
                    for channel in 0..<Int(buffer.format.channelCount) {
                        part.floatChannelData![channel].update(from: buffer.floatChannelData![channel].advanced(by: Int(start)), count: Int(keep))
                    }
                    try output.write(from: part)
                } else {
                    try output.write(from: buffer)
                }
                written += keep
            }
            progress(Double(written) / Double(max(total, 1)))
        }
        engine.stop()
        output.close()
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }
}
