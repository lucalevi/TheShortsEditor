@preconcurrency import AVFoundation
import CryptoKit
import EditorCore
import Foundation

/// Plays a clip's sound through a voice effect and/or an EQ preset. Like `VoiceCleaner`, it
/// works offline, once per file and setting, on this Mac: the result is kept in the app's caches
/// and the composition uses it in place of the file's own sound (same length, same timing).
public nonisolated enum SoundProcessor {
    public enum ProcessError: LocalizedError {
        case failed

        public var errorDescription: String? { "The sound effect couldn't be made." }
    }

    /// What a processed copy is made from and with.
    public struct Recipe: Hashable, Sendable {
        public var effect: VoiceEffect?
        public var equalizer: SoundEQ?

        public init(effect: VoiceEffect?, equalizer: SoundEQ?) {
            self.effect = effect
            self.equalizer = equalizer
        }

        public init(_ clip: Clip) {
            self.init(effect: clip.voiceEffect, equalizer: clip.equalizer)
        }

        public var isEmpty: Bool { effect == nil && equalizer == nil }
        var key: String { "\(effect?.rawValue ?? "-")|\(equalizer?.rawValue ?? "-")|v1" }
    }

    static var folder: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appending(path: "Shorts Editor/Sound Effects Applied", directoryHint: .isDirectory)
    }

    /// Where the processed sound of `source` is kept (named after the file and the recipe).
    public static func processedURL(for source: URL, recipe: Recipe) -> URL {
        let values = try? source.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let key = "\(source.path)|\(values?.fileSize ?? 0)|\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(recipe.key)"
        let digest = SHA256.hash(data: Data(key.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return folder.appending(path: "\(digest).m4a")
    }

    public static func existingProcessedURL(for source: URL, recipe: Recipe) -> URL? {
        guard !recipe.isEmpty else { return nil }
        let url = processedURL(for: source, recipe: recipe)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// The file whose sound `clip` should be processed from: its cleaned-up copy when it uses
    /// one (and it has been made), otherwise the file itself.
    public static func baseURL(for clip: Clip, media: MediaAsset) -> URL {
        clip.cleansVoice ? VoiceCleaner.existingCleanedURL(for: media.url) ?? media.url : media.url
    }

    /// The file `clip`'s sound plays from: processed, cleaned, or the original, depending on what
    /// it asks for and what has been made. While a processed copy it needs isn't made yet, the
    /// sound plays unprocessed.
    public static func playedURL(for clip: Clip, media: MediaAsset) -> URL {
        let base = baseURL(for: clip, media: media)
        let recipe = Recipe(clip)
        guard !recipe.isEmpty else { return base }
        return existingProcessedURL(for: base, recipe: recipe) ?? base
    }

    /// Makes the processed sound of `source` (or returns it if it exists), reporting progress 0…1.
    /// `source` is the file's sound as it would otherwise play (the cleaned-up copy, if used).
    @concurrent
    public static func process(_ source: URL, recipe: Recipe, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        if let existing = existingProcessedURL(for: source, recipe: recipe) { return existing }
        let destination = processedURL(for: source, recipe: recipe)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let input = try AVAudioFile(forReading: source)
        // Effects work in stereo; a mixer in front turns a mono file into stereo.
        guard let format = AVAudioFormat(standardFormatWithSampleRate: input.processingFormat.sampleRate, channels: 2) else {
            throw ProcessError.failed
        }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let converter = AVAudioMixerNode()
        engine.attach(player)
        engine.attach(converter)
        engine.connect(player, to: converter, format: input.processingFormat)
        let chain = units(for: recipe, sampleRate: format.sampleRate)
        var previous: AVAudioNode = converter
        for unit in chain {
            engine.attach(unit)
            engine.connect(previous, to: unit, format: format)
            previous = unit
        }
        engine.connect(previous, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try engine.start()
        OfflinePlayback.schedule(input, on: player)
        player.play()

        var dsp = SampleShaper(effect: recipe.effect, sampleRate: format.sampleRate, channels: Int(format.channelCount))
        // Effects run a little late: skip that much at the start and render that much more at the end.
        let latency = AVAudioFramePosition((chain.reduce(0) { $0 + $1.auAudioUnit.latency } * format.sampleRate).rounded())
        let total = input.length
        let temporary = destination.deletingLastPathComponent().appending(path: UUID().uuidString + ".m4a")
        let output = try AVAudioFile(
            forWriting: temporary,
            settings: [
                AVFormatIDKey: kAudioFormatAppleLossless,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVEncoderBitDepthHintKey: 24,
            ], commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: engine.manualRenderingMaximumFrameCount) else {
            throw ProcessError.failed
        }
        var rendered: AVAudioFramePosition = 0
        var written: AVAudioFramePosition = 0
        while written < total {
            try Task.checkCancellation()
            let frames = AVAudioFrameCount(min(AVAudioFramePosition(buffer.frameCapacity), total + latency - rendered))
            guard frames > 0 else { break }
            let status = try engine.renderOffline(frames, to: buffer)
            guard status == .success else { throw ProcessError.failed }
            var start = AVAudioFramePosition(0)
            if rendered < latency { start = min(latency - rendered, AVAudioFramePosition(buffer.frameLength)) }
            rendered += AVAudioFramePosition(buffer.frameLength)
            let keep = min(AVAudioFramePosition(buffer.frameLength) - start, total - written)
            if keep > 0 {
                guard let part = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(keep)) else { throw ProcessError.failed }
                part.frameLength = AVAudioFrameCount(keep)
                for channel in 0..<Int(buffer.format.channelCount) {
                    part.floatChannelData![channel].update(from: buffer.floatChannelData![channel].advanced(by: Int(start)), count: Int(keep))
                }
                dsp.process(part)
                try output.write(from: part)
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

    /// The Audio Units for a recipe, in playing order: pitch, tone, then echo and space.
    static func units(for recipe: Recipe, sampleRate: Double) -> [AVAudioUnit] {
        var units: [AVAudioUnit] = []
        func pitch(_ cents: Float) {
            let unit = AVAudioUnitTimePitch()
            unit.pitch = cents
            units.append(unit)
        }
        func eq(_ bands: [(AVAudioUnitEQFilterType, Float, Float, Float)]) {
            // (type, frequency, gain dB, bandwidth in octaves)
            let unit = AVAudioUnitEQ(numberOfBands: bands.count)
            for (band, setting) in zip(unit.bands, bands) {
                band.filterType = setting.0
                band.frequency = setting.1
                band.gain = setting.2
                band.bandwidth = setting.3
                band.bypass = false
            }
            units.append(unit)
        }
        switch recipe.effect {
        case .chipmunk: pitch(800)
        case .deep: pitch(-600)
        case .robot:
            let comb = AVAudioUnitDelay()
            comb.delayTime = 0.012
            comb.feedback = 55
            comb.lowPassCutoff = 8000
            comb.wetDryMix = 45
            units.append(comb)
        case .telephone:
            eq([(.highPass, 400, 0, 0.5), (.lowPass, 3200, 0, 0.5), (.parametric, 1500, 6, 1)])
        case .radio:
            eq([(.highPass, 250, 0, 0.5), (.lowPass, 5000, 0, 0.5), (.parametric, 1800, 5, 1.2)])
        case .megaphone:
            eq([(.highPass, 600, 0, 0.5), (.lowPass, 4000, 0, 0.5), (.parametric, 2000, 9, 1)])
        case .echo:
            let delay = AVAudioUnitDelay()
            delay.delayTime = 0.28
            delay.feedback = 38
            delay.lowPassCutoff = 6000
            delay.wetDryMix = 30
            units.append(delay)
        case .underwater:
            pitch(-150)
            eq([(.lowPass, 450, 0, 0.5), (.lowPass, 600, 0, 0.5)])
            let reverb = AVAudioUnitReverb()
            reverb.loadFactoryPreset(.largeHall)
            reverb.wetDryMix = 35
            units.append(reverb)
        case nil:
            break
        }
        switch recipe.equalizer {
        case .voice:
            eq([(.highPass, 90, 0, 0.5), (.parametric, 300, -3, 1), (.parametric, 3200, 3, 1.2)])
        case .music:
            eq([(.lowShelf, 100, 3, 1), (.highShelf, 8000, 2.5, 1)])
        case .lessBass:
            eq([(.highPass, 140, 0, 0.5), (.lowShelf, 220, -6, 1)])
        case nil:
            break
        }
        return units
    }
}

/// What can't be done with Apple's Audio Units: ring modulation for the robot, and the overdrive
/// of a cheap speaker for the telephone, radio and megaphone.
nonisolated struct SampleShaper {
    let effect: VoiceEffect?
    let sampleRate: Double
    var phase: [Double]

    init(effect: VoiceEffect?, sampleRate: Double, channels: Int) {
        self.effect = effect
        self.sampleRate = sampleRate
        phase = Array(repeating: 0, count: channels)
    }

    /// Overdrive: how hard the sound is pushed into the curve (1 = barely).
    var drive: Float? {
        switch effect {
        case .telephone: 2.5
        case .radio: 1.8
        case .megaphone: 5
        default: nil
        }
    }

    mutating func process(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData else { return }
        let count = Int(buffer.frameLength)
        for channel in 0..<Int(buffer.format.channelCount) {
            let samples = data[channel]
            if effect == .robot {
                let step = 2 * Double.pi * 55 / sampleRate
                var p = phase[channel]
                for i in 0..<count {
                    samples[i] = samples[i] * Float(0.35 + 0.65 * sin(p)) * 1.3
                    p += step
                }
                phase[channel] = p.truncatingRemainder(dividingBy: 2 * .pi)
            }
            if let drive {
                let norm = tanhf(drive)
                for i in 0..<count { samples[i] = tanhf(samples[i] * drive) / norm * 0.9 }
            }
        }
    }
}

/// Rendering a file offline through an audio engine.
nonisolated enum OfflinePlayback {
    /// Queues the whole file on the player. Not async on purpose: nothing waits for the file to finish
    /// playing (the engine is pulled frame by frame), and in an async function the compiler asks for
    /// the async form of `scheduleFile`, which would wait for the end.
    static func schedule(_ file: AVAudioFile, on player: AVAudioPlayerNode) {
        player.scheduleFile(file, at: nil, completionHandler: nil)
    }
}
