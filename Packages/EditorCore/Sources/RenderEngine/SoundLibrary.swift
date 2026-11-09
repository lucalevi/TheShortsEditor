@preconcurrency import AVFoundation
import Foundation

/// The sound effects that come with the app. They are made by the app itself the first time they
/// are needed (no recordings to license), and kept in its Application Support folder.
/// A group of sound effects, as iMovie sorts its library.
public nonisolated enum SoundEffectGroup: String, CaseIterable, Identifiable, Sendable {
    case whooshes, hits, risers, interface, cartoon, ambience

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .whooshes: "Whooshes"
        case .hits: "Hits"
        case .risers: "Risers"
        case .interface: "Taps and alerts"
        case .cartoon: "Cartoon"
        case .ambience: "Ambience"
        }
    }

    public var effects: [SoundEffect] { SoundEffect.allCases.filter { $0.group == self } }
}

/// The sound effects that come with the app. They are made by the app itself the first time they
/// are needed (no recordings to license), and kept in its Application Support folder.
public nonisolated enum SoundEffect: String, CaseIterable, Identifiable, Sendable {
    case whoosh, swipe, deepWhoosh, flyBy, zip
    case boom, punch, thud, cinematicHit, clap
    case riser, fall, tension, rewind
    case pop, click, ding, notification, typing, shutter, correct, wrong, coin, tick
    case boing, slideWhistle, bonk, laser, spring
    case rain, wind, ocean, roomTone, heartbeat

    public var id: String { rawValue }

    public var group: SoundEffectGroup {
        switch self {
        case .whoosh, .swipe, .deepWhoosh, .flyBy, .zip: .whooshes
        case .boom, .punch, .thud, .cinematicHit, .clap: .hits
        case .riser, .fall, .tension, .rewind: .risers
        case .pop, .click, .ding, .notification, .typing, .shutter, .correct, .wrong, .coin, .tick: .interface
        case .boing, .slideWhistle, .bonk, .laser, .spring: .cartoon
        case .rain, .wind, .ocean, .roomTone, .heartbeat: .ambience
        }
    }

    public var displayName: String {
        switch self {
        case .whoosh: "Whoosh"
        case .swipe: "Swipe"
        case .deepWhoosh: "Deep Whoosh"
        case .flyBy: "Fly-By"
        case .zip: "Zip"
        case .boom: "Boom"
        case .punch: "Punch"
        case .thud: "Thud"
        case .cinematicHit: "Big Hit"
        case .clap: "Clap"
        case .riser: "Riser"
        case .fall: "Fall"
        case .tension: "Tension"
        case .rewind: "Rewind"
        case .pop: "Pop"
        case .click: "Click"
        case .ding: "Ding"
        case .notification: "Notification"
        case .typing: "Typing"
        case .shutter: "Camera"
        case .correct: "Correct"
        case .wrong: "Wrong"
        case .coin: "Coin"
        case .tick: "Clock Tick"
        case .boing: "Boing"
        case .slideWhistle: "Slide Whistle"
        case .bonk: "Bonk"
        case .laser: "Laser"
        case .spring: "Spring"
        case .rain: "Rain"
        case .wind: "Wind"
        case .ocean: "Waves"
        case .roomTone: "Room Tone"
        case .heartbeat: "Heartbeat"
        }
    }

    /// When creators use it.
    public var hint: String {
        switch self {
        case .whoosh: "On a cut or a zoom"
        case .swipe: "A quick change of picture"
        case .deepWhoosh: "A slow, heavy transition"
        case .flyBy: "Something passing the camera"
        case .zip: "Text or a sticker flying in"
        case .boom: "The reveal itself"
        case .punch: "A punch-in zoom, a hard cut"
        case .thud: "Something dropped, a full stop"
        case .cinematicHit: "A title slamming in"
        case .clap: "Start, or a beat to cut on"
        case .riser: "Building up to a reveal"
        case .fall: "After the drop, coming down"
        case .tension: "Suspense before the answer"
        case .rewind: "Going back in time"
        case .pop: "When text or a picture appears"
        case .click: "A list, a tap on screen"
        case .ding: "A right answer, a tip"
        case .notification: "A message arrives"
        case .typing: "Text being typed"
        case .shutter: "A photo, a freeze frame"
        case .correct: "Yes! That's it"
        case .wrong: "Nope, a mistake"
        case .coin: "Money, a reward, points"
        case .tick: "Waiting, a countdown"
        case .boing: "Something bouncy or silly"
        case .slideWhistle: "A fail, a fall"
        case .bonk: "A comic hit on the head"
        case .laser: "Sci-fi, zapping something"
        case .spring: "A jump, something popping up"
        case .rain: "Calm, cosy background"
        case .wind: "Outdoors, empty places"
        case .ocean: "The sea, relaxing"
        case .roomTone: "Fills silent gaps quietly"
        case .heartbeat: "Nerves, a tense moment"
        }
    }

    public var systemImage: String {
        switch self {
        case .whoosh, .swipe, .deepWhoosh, .flyBy, .wind: "wind"
        case .zip: "bolt.horizontal"
        case .boom, .cinematicHit: "burst"
        case .punch, .thud, .bonk: "hand.raised.fingers.spread"
        case .clap: "hands.clap"
        case .riser, .tension: "arrow.up.right"
        case .fall: "arrow.down.right"
        case .rewind: "backward"
        case .pop: "bubble.left"
        case .click: "cursorarrow.click"
        case .ding, .notification: "bell"
        case .typing: "keyboard"
        case .shutter: "camera"
        case .correct: "checkmark.circle"
        case .wrong: "xmark.circle"
        case .coin: "dollarsign.circle"
        case .tick: "clock"
        case .boing, .spring: "arrow.up.and.down"
        case .slideWhistle: "music.note"
        case .laser: "sparkles"
        case .rain, .ocean: "cloud.rain"
        case .roomTone: "house"
        case .heartbeat: "heart"
        }
    }

    var seconds: Double {
        switch self {
        case .whoosh: 0.7
        case .swipe: 0.3
        case .deepWhoosh: 1.4
        case .flyBy: 1.6
        case .zip: 0.35
        case .boom: 1.4
        case .punch: 0.35
        case .thud: 0.5
        case .cinematicHit: 2.5
        case .clap: 0.3
        case .riser: 2.0
        case .fall: 1.5
        case .tension: 4.0
        case .rewind: 1.2
        case .pop: 0.15
        case .click: 0.05
        case .ding: 1.3
        case .notification: 0.6
        case .typing: 2.0
        case .shutter: 0.35
        case .correct: 0.7
        case .wrong: 0.6
        case .coin: 0.6
        case .tick: 4.0
        case .boing: 0.8
        case .slideWhistle: 1.2
        case .bonk: 0.4
        case .laser: 0.5
        case .spring: 0.7
        case .rain, .wind, .ocean, .roomTone: 12
        case .heartbeat: 4.8
        }
    }

    /// How loud it is made: background sounds sit well under the voice.
    var peak: Double {
        switch group {
        case .ambience: self == .heartbeat ? 0.7 : self == .roomTone ? 0.08 : 0.35
        default: 0.8
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

    /// The sound, one value per sample, peaking at `peak`.
    func samples() -> [Float] {
        let rate = Self.sampleRate
        let count = Int(seconds * rate)
        var noiseState: UInt32 = 0x1234_5678
        func noise() -> Double {
            noiseState = noiseState &* 1_664_525 &+ 1_013_904_223
            return Double(noiseState) / Double(UInt32.max) * 2 - 1
        }
        var out = [Double](repeating: 0, count: count)
        var low = 0.0, low2 = 0.0, phase = 0.0, phase2 = 0.0
        /// One step of a one-pole low-pass filter at `cutoff` Hz.
        func lowPass(_ x: Double, _ state: inout Double, _ cutoff: Double) -> Double {
            state += (1 - exp(-2 * .pi * cutoff / rate)) * (x - state)
            return state
        }
        /// A short, sharp knock at `t` seconds into a hit starting at `at`.
        func knock(_ t: Double, at: Double, frequency: Double, decay: Double) -> Double {
            let d = t - at
            guard d >= 0 else { return 0 }
            return sin(2 * .pi * frequency * d) * exp(-d * decay) * min(d * 2000, 1)
        }
        func tone(_ t: Double, _ f: Double) -> Double { sin(2 * .pi * f * t) }
        // Fixed "random" moments for typing, rain drops and so on.
        var eventState: UInt32 = 0x9E37_79B9
        func nextRandom() -> Double {
            eventState = eventState &* 1_664_525 &+ 1_013_904_223
            return Double(eventState) / Double(UInt32.max)
        }
        let typingHits = (0..<14).map { Double($0) * 0.14 + nextRandom() * 0.05 }
        let drops = (0..<180).map { _ in (nextRandom() * seconds, 1500 + nextRandom() * 3000) }

        for i in 0..<count {
            let t = Double(i) / rate
            let p = t / seconds
            let value: Double
            switch self {
            case .whoosh, .swipe:
                // Noise through a filter that opens and closes, swelling and fading.
                value = lowPass(noise(), &low, 300 + 5000 * sin(.pi * p)) * sin(.pi * p)
            case .deepWhoosh:
                value = lowPass(noise(), &low, 120 + 1500 * sin(.pi * p)) * pow(sin(.pi * p), 1.5)
            case .flyBy:
                // Rises as it comes, drops in pitch as it passes.
                let near = exp(-pow((p - 0.5) * 5, 2))
                phase += 2 * .pi * (p < 0.5 ? 320 : 230) / rate
                value = (lowPass(noise(), &low, 400 + 4000 * near) + 0.25 * sin(phase)) * near
            case .zip:
                value = lowPass(noise(), &low, 800 + 9000 * p) * sin(.pi * p) * (1 + 0.5 * sin(2 * .pi * 60 * t))
            case .pop:
                phase += 2 * .pi * (220 + 700 * exp(-p * 6)) / rate
                value = sin(phase) * exp(-p * 7)
            case .click:
                value = noise() * exp(-p * 12)
            case .ding:
                value = (tone(t, 1320) + 0.45 * tone(t, 2640) + 0.2 * tone(t, 3960)) * exp(-p * 5) * min(t * 400, 1)
            case .riser:
                phase += 2 * .pi * (180 + 1100 * p * p) / rate
                value = (0.6 * sin(phase) + 0.5 * lowPass(noise(), &low, 500 + 6000 * p)) * p * p * (p > 0.97 ? (1 - p) / 0.03 : 1)
            case .fall:
                phase += 2 * .pi * (900 * pow(1 - p, 2) + 60) / rate
                value = (0.6 * sin(phase) + 0.4 * lowPass(noise(), &low, 6000 * (1 - p) + 200)) * pow(1 - p, 1.5) * min(t * 50, 1)
            case .tension:
                // Two close low tones beating, slowly getting louder, with a high shimmer.
                value = (tone(t, 55) + tone(t, 58.3) + 0.15 * tone(t, 880 + 30 * p) * sin(2 * .pi * 6 * t)) * (0.2 + 0.8 * p) * min((1 - p) * 30, 1)
            case .rewind:
                // Fast chattering going up, like tape going backwards.
                phase += 2 * .pi * (300 + 1500 * p) / rate
                value = sin(phase) * (0.5 + 0.5 * sin(2 * .pi * (20 + 30 * p) * t)) * sin(.pi * p)
            case .boom:
                phase += 2 * .pi * (35 + 45 * exp(-p * 4)) / rate
                value = (sin(phase) + 0.8 * lowPass(noise(), &low, 400) * exp(-p * 10)) * exp(-p * 3.5) * min(t * 300, 1)
            case .punch:
                phase += 2 * .pi * (60 + 120 * exp(-t * 40)) / rate
                value = (sin(phase) * exp(-t * 14) + 0.6 * noise() * exp(-t * 60)) * min(t * 3000, 1)
            case .thud:
                phase += 2 * .pi * (45 + 60 * exp(-t * 30)) / rate
                value = (sin(phase) + 0.3 * lowPass(noise(), &low, 300)) * exp(-t * 11) * min(t * 2000, 1)
            case .cinematicHit:
                phase += 2 * .pi * (40 + 80 * exp(-t * 8)) / rate
                let body = sin(phase) * exp(-t * 1.6)
                let crack = lowPass(noise(), &low, 3000) * exp(-t * 12)
                let tail = lowPass(noise(), &low2, 250) * exp(-t * 1.2) * 0.5
                value = (body + crack + tail) * min(t * 1500, 1)
            case .clap:
                // A few quick bursts of noise, the way hands slap.
                let bursts = [0.0, 0.008, 0.017, 0.024]
                value = bursts.reduce(0.0) { sum, at in t >= at ? sum + exp(-(t - at) * (at == 0.024 ? 25 : 300)) : sum } * lowPass(noise(), &low, 2500)
            case .notification:
                value = (t < 0.15 ? tone(t, 988) : tone(t, 1319)) * exp(-(t < 0.15 ? t : t - 0.15) * 7) * min(t * 400, 1) * (t > 0.14 && t < 0.15 ? 0 : 1)
            case .typing:
                value = typingHits.reduce(0.0) { sum, at in sum + (t >= at ? knock(t, at: at, frequency: 2200, decay: 180) + 0.5 * noise() * exp(-(t - at) * 300) : 0) }
            case .shutter:
                value = noise() * (exp(-t * 120) + (t > 0.12 ? exp(-(t - 0.12) * 90) : 0)) * lowPass(1, &low, 4000)
            case .correct:
                let f = t < 0.12 ? 1047.0 : 1568.0
                value = (tone(t, f) + 0.3 * tone(t, f * 2)) * exp(-(t < 0.12 ? t : t - 0.12) * 6) * min(t * 400, 1)
            case .wrong:
                phase += 2 * .pi * (t < 0.25 ? 220 : 180) / rate
                value = (sin(phase) > 0 ? 0.6 : -0.6) * lowPass(1, &low, 30) * (t < 0.23 || t > 0.27 ? 1 : 0) * min((seconds - t) * 20, 1)
            case .coin:
                let f = t < 0.08 ? 988.0 : 1319.0
                value = (sin(2 * .pi * f * t) > 0 ? 0.5 : -0.5) * exp(-max(t - 0.08, 0) * 6)
            case .tick:
                let beat = t.truncatingRemainder(dividingBy: 0.5)
                value = knock(beat, at: 0, frequency: Int(t / 0.5) % 2 == 0 ? 3000 : 2400, decay: 250)
            case .boing:
                phase += 2 * .pi * (180 + 120 * sin(2 * .pi * 12 * t) * exp(-p * 3)) / rate
                value = sin(phase) * exp(-p * 3) * min(t * 400, 1)
            case .slideWhistle:
                phase += 2 * .pi * (1400 - 1000 * p + 15 * sin(2 * .pi * 6 * t)) / rate
                value = sin(phase) * min(t * 20, 1) * min((1 - p) * 10, 1)
            case .bonk:
                value = (knock(t, at: 0, frequency: 520, decay: 22) + 0.6 * knock(t, at: 0, frequency: 1310, decay: 30)) + 0.3 * noise() * exp(-t * 200)
            case .laser:
                phase += 2 * .pi * (2500 * exp(-p * 4) + 200) / rate
                value = sin(phase) * exp(-p * 2) * min(t * 1000, 1)
            case .spring:
                phase += 2 * .pi * (300 + 500 * p) / rate
                value = sin(phase) * (0.5 + 0.5 * sin(2 * .pi * 25 * t)) * exp(-p * 2.5) * min(t * 400, 1)
            case .rain:
                var drop = 0.0
                for (at, f) in drops where t >= at && t - at < 0.03 { drop += knock(t, at: at, frequency: f, decay: 200) * 0.3 }
                value = lowPass(noise(), &low, 3500) * 0.6 + drop
            case .wind:
                let gust = 0.55 + 0.45 * sin(2 * .pi * 0.17 * t) * sin(2 * .pi * 0.07 * t + 1)
                value = lowPass(lowPass(noise(), &low, 200 + 700 * gust), &low2, 900) * gust * 3
            case .ocean:
                let wave = pow(0.5 + 0.5 * sin(2 * .pi * t / 6 - .pi / 2), 2)
                value = lowPass(noise(), &low, 300 + 2500 * wave) * (0.2 + 0.8 * wave)
            case .roomTone:
                value = lowPass(lowPass(noise(), &low, 400), &low2, 400) + 0.02 * tone(t, 60)
            case .heartbeat:
                let beat = t.truncatingRemainder(dividingBy: 0.8)
                value = knock(beat, at: 0, frequency: 55, decay: 18) + 0.7 * knock(beat, at: 0.22, frequency: 50, decay: 20)
            }
            out[i] = value
        }
        // Long background sounds start and end softly, so they don't click in or out.
        if group == .ambience {
            let edge = Int(0.3 * rate)
            for i in 0..<min(edge, count) {
                out[i] *= Double(i) / Double(edge)
                out[count - 1 - i] *= Double(i) / Double(edge)
            }
        }
        let loudest = out.map(abs).max() ?? 1
        return out.map { Float($0 / max(loudest, 0.0001) * peak) }
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
