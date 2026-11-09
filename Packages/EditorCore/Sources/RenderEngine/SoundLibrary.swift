@preconcurrency import AVFoundation
import Foundation

/// The sound effects that come with the app. They are made by the app itself the first time they
/// are needed (no recordings to license), and kept in its Application Support folder.
public nonisolated enum SoundEffect: String, CaseIterable, Identifiable, Sendable {
    case whoosh, swipe, pop, click, ding, riser, boom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .whoosh: "Whoosh"
        case .swipe: "Swipe"
        case .pop: "Pop"
        case .click: "Click"
        case .ding: "Ding"
        case .riser: "Riser"
        case .boom: "Boom"
        }
    }

    /// When creators use it.
    public var hint: String {
        switch self {
        case .whoosh: "On a cut or a zoom"
        case .swipe: "A quick change of picture"
        case .pop: "When text or a picture appears"
        case .click: "A list, a tap on screen"
        case .ding: "A right answer, a tip"
        case .riser: "Building up to a reveal"
        case .boom: "The reveal itself"
        }
    }

    public var systemImage: String {
        switch self {
        case .whoosh, .swipe: "wind"
        case .pop: "bubble.left"
        case .click: "cursorarrow.click"
        case .ding: "bell"
        case .riser: "arrow.up.right"
        case .boom: "burst"
        }
    }

    var seconds: Double {
        switch self {
        case .whoosh: 0.7
        case .swipe: 0.3
        case .pop: 0.15
        case .click: 0.05
        case .ding: 1.3
        case .riser: 2.0
        case .boom: 1.4
        }
    }

    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "Shorts Editor/Sound Effects", directoryHint: .isDirectory)
    }

    /// The effect's file, made now if it doesn't exist yet.
    public func fileURL() throws -> URL {
        let url = Self.folder.appending(path: "\(displayName).caf")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        try write(to: url)
        return url
    }

    static let sampleRate = 48_000.0

    /// The sound, one value per sample, peaking at 0.8.
    func samples() -> [Float] {
        let rate = Self.sampleRate
        let count = Int(seconds * rate)
        var noiseState: UInt32 = 0x1234_5678
        func noise() -> Double {
            noiseState = noiseState &* 1_664_525 &+ 1_013_904_223
            return Double(noiseState) / Double(UInt32.max) * 2 - 1
        }
        var out = [Double](repeating: 0, count: count)
        var low = 0.0, phase = 0.0
        for i in 0..<count {
            let t = Double(i) / rate
            let p = t / seconds
            switch self {
            case .whoosh, .swipe:
                // Noise through a filter that opens and closes, swelling and fading.
                let cutoff = 300 + 5000 * sin(.pi * p)
                let a = 1 - exp(-2 * .pi * cutoff / rate)
                low += a * (noise() - low)
                out[i] = low * sin(.pi * p)
            case .pop:
                phase += 2 * .pi * (220 + 700 * exp(-p * 6)) / rate
                out[i] = sin(phase) * exp(-p * 7)
            case .click:
                out[i] = noise() * exp(-p * 12)
            case .ding:
                out[i] = (sin(2 * .pi * 1320 * t) + 0.45 * sin(2 * .pi * 2640 * t) + 0.2 * sin(2 * .pi * 3960 * t)) * exp(-p * 5) * min(t * 400, 1)
            case .riser:
                phase += 2 * .pi * (180 + 1100 * p * p) / rate
                let a = 1 - exp(-2 * .pi * (500 + 6000 * p) / rate)
                low += a * (noise() - low)
                out[i] = (0.6 * sin(phase) + 0.5 * low) * p * p * (p > 0.97 ? (1 - p) / 0.03 : 1)
            case .boom:
                phase += 2 * .pi * (35 + 45 * exp(-p * 4)) / rate
                let a = 1 - exp(-2 * .pi * 400 / rate)
                low += a * (noise() - low)
                out[i] = (sin(phase) + 0.8 * low * exp(-p * 10)) * exp(-p * 3.5) * min(t * 300, 1)
            }
        }
        let peak = out.map(abs).max() ?? 1
        return out.map { Float($0 / max(peak, 0.0001) * 0.8) }
    }

    func write(to url: URL) throws {
        let values = samples()
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(values.count))
        else { throw CocoaError(.fileWriteUnknown) }
        buffer.frameLength = AVAudioFrameCount(values.count)
        for channel in 0..<2 {
            values.withUnsafeBufferPointer { buffer.floatChannelData![channel].update(from: $0.baseAddress!, count: values.count) }
        }
        let temporary = url.deletingLastPathComponent().appending(path: UUID().uuidString + ".caf")
        let file = try AVAudioFile(forWriting: temporary, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: Self.sampleRate, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
        ])
        try file.write(from: buffer)
        file.close()
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: temporary, to: url)
    }
}
