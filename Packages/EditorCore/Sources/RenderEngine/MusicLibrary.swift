import Accelerate
@preconcurrency import AVFoundation
import EditorCore
import Foundation

/// The background music of the styles (`MusicMood`), made by the app itself the first time it is
/// needed, like the sound effects: no recordings, so nothing to license and nothing YouTube can
/// claim. Each track is a short intro and then a 16-bar loop repeated to past YouTube's 3-minute
/// limit, built bar by bar from time 0, so `Project.fitMoodMusic()` can end a Short on the beat.
public nonisolated enum MusicLibrary {
    static let sampleRate = 44_100.0
    /// Long enough for the longest Short, with a little to spare.
    static let length = Project.maxDuration.seconds + 4
    /// Bumped when the music changes, so old files are made again.
    static let version = 1

    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "Shorts Editor/Music/\(version)", directoryHint: .isDirectory)
    }

    /// The mood's music file, made now (in the background, a few seconds) if it doesn't exist yet.
    public static func fileURL(for mood: MusicMood) async throws -> URL {
        let url = folder.appending(path: "\(mood.displayName).m4a")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        try await Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let music = render(mood, seconds: length)
            try write(music, to: url)
        }.value
        return url
    }

    // MARK: Writing

    static func write(_ music: (left: [Float], right: [Float]), to url: URL) throws {
        let count = music.left.count
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count))
        else { throw CocoaError(.fileWriteUnknown) }
        buffer.frameLength = AVAudioFrameCount(count)
        music.left.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: count) }
        music.right.withUnsafeBufferPointer { buffer.floatChannelData![1].update(from: $0.baseAddress!, count: count) }
        let temporary = url.deletingLastPathComponent().appending(path: UUID().uuidString + ".m4a")
        do {
            let file = try AVAudioFile(forWriting: temporary, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000,
            ])
            try file.write(from: buffer)
            file.close()
        }
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: temporary, to: url)
    }

    // MARK: Making the music

    /// The mood's music, `seconds` long, peaking just under full scale.
    static func render(_ mood: MusicMood, seconds: Double) -> (left: [Float], right: [Float]) {
        let arrangement = Arrangement(mood)
        let bar = Int((240 / mood.tempo * sampleRate).rounded())
        let introBars = 2, loopBars = 16
        var mix = Mix(count: bar * (introBars + loopBars))
        var notes = NoteCache()
        for index in 0..<(introBars + loopBars) {
            let isIntro = index < introBars
            let loopBar = isIntro ? 0 : index - introBars
            arrangement.play(bar: loopBar, intro: isIntro, into: &mix, at: index * bar, barLength: bar, notes: &notes)
        }
        mix.finish()
        // Intro once, then the loop over and over.
        let total = Int(seconds * sampleRate)
        let loopStart = introBars * bar
        var left = Array(mix.left), right = Array(mix.right)
        left.reserveCapacity(total + mix.count)
        right.reserveCapacity(total + mix.count)
        while left.count < total {
            left.append(contentsOf: mix.left[loopStart...])
            right.append(contentsOf: mix.right[loopStart...])
        }
        return (Array(left.prefix(total)), Array(right.prefix(total)))
    }

    /// A stereo buffer that notes are added into.
    nonisolated struct Mix {
        var left: [Float]
        var right: [Float]
        var count: Int { left.count }

        init(count: Int) {
            left = [Float](repeating: 0, count: count)
            right = [Float](repeating: 0, count: count)
        }

        /// Adds `samples` at `start`, `pan` −1 (left) … 1 (right). Whatever runs past the end
        /// wraps round to the start of the loop, so the loop joins without a gap or a click.
        mutating func add(_ samples: [Float], at start: Int, gain: Float, pan: Float = 0, loopStart: Int) {
            let l = gain * min(1, 1 - pan), r = gain * min(1, 1 + pan)
            let loopLength = count - loopStart
            let total = count
            left.withUnsafeMutableBufferPointer { left in
                right.withUnsafeMutableBufferPointer { right in
                    samples.withUnsafeBufferPointer { samples in
                        for offset in 0..<samples.count {
                            var i = start + offset
                            if i >= total {
                                guard loopLength > 0 else { return }
                                i = loopStart + (i - total) % loopLength
                            }
                            left[i] += samples[offset] * l
                            right[i] += samples[offset] * r
                        }
                    }
                }
            }
        }

        /// Gentle saturation, then the loudest moment just under full scale.
        mutating func finish() {
            let loudest = max(vDSP.maximumMagnitude(left), vDSP.maximumMagnitude(right), 0.0001)
            for channel in [0, 1] {
                var values = vDSP.multiply(1.3 / loudest, channel == 0 ? left : right)
                values = vForce.tanh(values)
                values = vDSP.multiply(0.89 / tanh(1.3), values)
                if channel == 0 { left = values } else { right = values }
            }
        }
    }

    // MARK: Instruments

    nonisolated enum Sound {
        case pad, keys, pluck, square, bell, strings, bass, subBass
        case kick, boom, snare, clap, hat, shaker

        /// One note of the instrument at `frequency` Hz, `seconds` long (plus its tail).
        func note(_ frequency: Double, seconds: Double, rate: Double, noise: inout Noise) -> [Float] {
            let tail: Double = switch self {
            case .pad, .strings: 0.6
            case .keys, .bell: 1.2
            case .pluck, .square: 0.25
            case .bass, .subBass: 0.08
            default: 0
            }
            // Drums ring for their own length, whatever the step.
            let ring: Double = switch self {
            case .kick: 0.45
            case .boom: 2.2
            case .snare, .clap: 0.3
            case .hat: 0.08
            case .shaker: 0.1
            default: 0
            }
            let count = Int((max(seconds, ring) + tail) * rate)
            var out = [Float](repeating: 0, count: count)
            var low = 0.0
            for i in 0..<count {
                let t = Double(i) / rate
                let release = tail > 0 && t > seconds ? exp(-(t - seconds) / tail * 5) : 1
                func h(_ n: Double) -> Double { Wave.sine(frequency * n * t) }
                let value: Double
                switch self {
                case .pad:
                    let attack = min(t / 0.35, 1)
                    value = (h(1) + 0.5 * Wave.sine(frequency * 1.004 * t) + 0.25 * h(2) + 0.1 * h(3)) * attack * release * 0.5
                case .strings:
                    let attack = min(t / 0.25, 1)
                    let bow = 1 + 0.08 * Wave.sine(5.5 * t)
                    value = (h(1) + 0.6 * Wave.sine(frequency * 0.997 * t) + 0.45 * h(2) + 0.3 * h(3) + 0.15 * h(4)) * attack * release * bow * 0.4
                case .keys:
                    // A soft electric piano: a sine whose brightness fades quickly.
                    let bright = exp(-t * 7)
                    value = Wave.sine(frequency * t + 0.25 * bright * Wave.sine(frequency * t)) * exp(-t * 1.8) * min(t * 300, 1) * release
                case .pluck:
                    value = (h(1) + 0.5 * exp(-t * 18) * h(2) + 0.3 * exp(-t * 30) * h(3) + 0.15 * exp(-t * 40) * h(4)) * exp(-t * 9) * min(t * 800, 1) * release
                case .square:
                    value = (h(1) + h(3) / 3 + h(5) / 5 + h(7) / 7) * exp(-t * 7) * min(t * 800, 1) * release * 0.7
                case .bell:
                    value = (h(1) + 0.35 * Wave.sine(frequency * 2.76 * t) * exp(-t * 3) + 0.2 * h(4) * exp(-t * 5)) * exp(-t * 1.2) * min(t * 500, 1) * release
                case .bass:
                    value = (h(1) + 0.35 * h(2) + 0.12 * h(3)) * min(t * 200, 1) * exp(-t * 1.5) * release
                case .subBass:
                    value = (h(1) + 0.15 * h(2)) * min(t * 200, 1) * release
                case .kick:
                    let sweep = 45 * t + (110 / 30) * (1 - exp(-t * 30))
                    value = Wave.sine(sweep) * exp(-t * 7) * min(t * 2000, 1) * (t < 0.45 ? 1 : 0)
                case .boom:
                    let sweep = 38 * t + (70 / 12) * (1 - exp(-t * 12))
                    let rumble = lowPass(noise.next(), &low, 300, rate) * exp(-t * 6)
                    value = (Wave.sine(sweep) + 0.8 * rumble) * exp(-t * 2.2) * min(t * 1500, 1)
                case .snare:
                    let n = noise.next()
                    let bright = n - lowPass(n, &low, 1500, rate)
                    value = (0.8 * bright * exp(-t * 16) + 0.5 * Wave.sine(185 * t) * exp(-t * 25)) * (t < 0.3 ? 1 : 0)
                case .clap:
                    let bursts = [0.0, 0.009, 0.018, 0.026]
                    let env = bursts.reduce(0.0) { sum, at in t >= at ? sum + exp(-(t - at) * (at == 0.026 ? 22 : 280)) : sum }
                    let n = noise.next()
                    value = (n - lowPass(n, &low, 900, rate)) * env * 0.8 * (t < 0.3 ? 1 : 0)
                case .hat:
                    let n = noise.next()
                    value = (n - lowPass(n, &low, 7000, rate)) * exp(-t * 55) * (t < 0.08 ? 1 : 0)
                case .shaker:
                    let n = noise.next()
                    value = (n - lowPass(n, &low, 5000, rate)) * min(t * 60, 1) * exp(-t * 30) * (t < 0.1 ? 1 : 0)
                }
                out[i] = Float(value)
            }
            return out
        }
    }

    static func lowPass(_ x: Double, _ state: inout Double, _ cutoff: Double, _ rate: Double) -> Double {
        state += (1 - exp(-2 * .pi * cutoff / rate)) * (x - state)
        return state
    }

    /// Each different note is made once: chords and drum hits repeat all through a track.
    nonisolated struct NoteCache {
        private var notes: [String: [Float]] = [:]
        private var noise = Noise()

        mutating func samples(_ sound: Sound, _ midi: Int, seconds: Double, rate: Double) -> [Float] {
            let key = "\(sound) \(midi) \(Int(seconds * 1000))"
            if let made = notes[key] { return made }
            let made = sound.note(Arrangement.frequency(midi), seconds: seconds, rate: rate, noise: &noise)
            notes[key] = made
            return made
        }
    }

    /// Repeatable noise, so the music comes out the same every time.
    nonisolated struct Noise {
        var state: UInt32 = 0x1234_5678
        mutating func next() -> Double {
            state = state &* 1_664_525 &+ 1_013_904_223
            return Double(state) / Double(UInt32.max) * 2 - 1
        }
    }

    /// A sine from a table: much quicker than `sin` for the millions of samples a track needs.
    nonisolated enum Wave {
        static let size = 4096
        static let table: [Double] = (0..<size).map { sin(2 * .pi * Double($0) / Double(size)) }
        /// The sine of `cycles` whole turns.
        static func sine(_ cycles: Double) -> Double {
            let position = cycles - cycles.rounded(.down)
            return table[Int(position * Double(size)) & (size - 1)]
        }
    }

    // MARK: Arrangements

    /// What each mood plays: chords, instruments and drum patterns on a grid of 16 steps a bar.
    nonisolated struct Arrangement {
        let mood: MusicMood
        /// The key's root, as a MIDI note number, and the chords (notes above it), one a bar.
        var root = 60
        var chords: [[Int]] = []
        var chordSound: Sound = .pad
        /// Steps (0–15) where the chord is struck (a pad holds it for the bar).
        var chordSteps: [Int] = [0]
        var chordLength = 1.0
        var stabSound: Sound?
        var stabSteps: [Int] = []
        var bassSound: Sound = .bass
        var bassSteps: [Int] = [0]
        /// Bass note per step as an offset from the chord's root (default the root).
        var bassFifthSteps: Set<Int> = []
        var arpSound: Sound?
        var arpStep = 2
        var kick: [Int] = [], snare: [Int] = [], clap: [Int] = [], hat: [Int] = [], shaker: [Int] = []
        var boomEvery = 0
        /// Delay of the off-beat 16ths, as a fraction of a step (swing).
        var swing = 0.0
        var levels: (chords: Float, stabs: Float, bass: Float, arp: Float, drums: Float) = (0.5, 0.35, 0.7, 0.3, 0.8)

        init(_ mood: MusicMood) {
            self.mood = mood
            let major = (I: [0, 4, 7], ii: [2, 5, 9], IV: [5, 9, 12], V: [7, 11, 14], vi: [9, 12, 16])
            switch mood {
            case .upbeat:
                root = 60
                chords = [major.I, major.V, major.vi, major.IV]
                chordSound = .pad
                stabSound = .pluck
                stabSteps = [2, 6, 10, 14]
                bassSteps = [0, 2, 4, 6, 8, 10, 12, 14]
                kick = [0, 4, 8, 12]; clap = [4, 12]; hat = [2, 6, 10, 14]
                arpSound = .pluck; arpStep = 1
                levels = (0.35, 0.4, 0.7, 0.22, 0.85)
            case .chill:
                root = 62
                chords = [[2, 5, 9, 12], [7, 11, 14, 17], [0, 4, 7, 11], [9, 12, 16, 19]]
                chordSound = .keys
                chordSteps = [0, 6]
                chordLength = 0.4
                bassSound = .subBass
                bassSteps = [0, 7, 10]
                kick = [0, 7, 10]; snare = [4, 12]; hat = [0, 2, 4, 6, 8, 10, 12, 14]
                swing = 0.3
                arpSound = .bell; arpStep = 4
                levels = (0.5, 0, 0.75, 0.18, 0.6)
            case .dramatic:
                root = 57
                chords = [[0, 3, 7], [8, 12, 15], [3, 7, 10], [10, 14, 17]]
                chordSound = .strings
                bassSteps = [0, 2, 4, 6, 8, 10, 12, 14]
                kick = [0, 10]; snare = [8]
                boomEvery = 4
                hat = []
                arpSound = .pluck; arpStep = 2
                levels = (0.55, 0, 0.6, 0.2, 0.75)
            case .playful:
                root = 65
                chords = [major.I, major.vi, major.IV, major.V]
                chordSound = .pad
                stabSound = .square
                stabSteps = [2, 6, 10, 14]
                bassSteps = [0, 4, 8, 12]
                bassFifthSteps = [4, 12]
                kick = [0, 8]; clap = [4, 12]; shaker = Array(0..<16)
                arpSound = .square; arpStep = 2
                levels = (0.25, 0.35, 0.7, 0.2, 0.7)
            case .calm:
                root = 60
                chords = [[0, 4, 7, 11], [5, 9, 12, 16], [9, 12, 16, 19], [5, 9, 12, 16]]
                chordSound = .pad
                bassSound = .subBass
                bassSteps = [0]
                arpSound = .bell; arpStep = 4
                levels = (0.55, 0, 0.5, 0.25, 0)
            case .focus:
                root = 62
                chords = [major.vi, major.IV, major.I, major.V]
                chordSound = .pad
                stabSound = .pluck
                stabSteps = [0, 2, 4, 6, 8, 10, 12, 14]
                bassSteps = [0, 8]
                kick = [0, 8, 10]; snare = [4, 12]; hat = [2, 6, 10, 14]
                arpSound = nil
                levels = (0.3, 0.3, 0.65, 0, 0.55)
            }
        }

        static func frequency(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }

        /// Plays one bar of the loop (`bar` 0–15; the second half adds the arpeggio) or of the
        /// intro (chords and bass only) into `mix` at sample `start`.
        func play(bar: Int, intro: Bool, into mix: inout Mix, at start: Int, barLength: Int, notes: inout NoteCache) {
            let rate = MusicLibrary.sampleRate
            let step = Double(barLength) / 16
            let stepSeconds = step / rate
            let chord = chords[bar % chords.count].map { root + $0 }
            let loopStart = 2 * barLength
            func at(_ s: Int) -> Int {
                let delay = s % 2 == 1 ? swing * step : 0
                return start + Int(Double(s) * step + delay)
            }
            func add(_ sound: Sound, _ midi: Int, steps: Double, at s: Int, gain: Float, pan: Float = 0) {
                let samples = notes.samples(sound, midi, seconds: steps * stepSeconds, rate: rate)
                mix.add(samples, at: at(s), gain: gain, pan: pan, loopStart: loopStart)
            }

            // Chords: held for the bar, or struck where the pattern says.
            let chordSteps = chordSound == .pad || chordSound == .strings ? [0] : self.chordSteps
            for (number, s) in chordSteps.enumerated() {
                let length = chordSound == .pad || chordSound == .strings ? 16 : 16 * chordLength
                for (voice, note) in chord.enumerated() {
                    let pan: Float = chord.count > 1 ? Float(voice) / Float(chord.count - 1) * 0.6 - 0.3 : 0
                    add(chordSound, note, steps: length, at: s, gain: levels.chords / Float(chord.count) * (number == 0 ? 1 : 0.8), pan: pan)
                }
            }
            // Bass, an octave or two down.
            let bassRoot = chord[0] - 24
            for (index, s) in bassSteps.enumerated() {
                let next = index + 1 < bassSteps.count ? bassSteps[index + 1] : 16
                let note = bassFifthSteps.contains(s) ? bassRoot + 7 : bassRoot
                add(bassSound, note, steps: Double(next - s) * 0.9, at: s, gain: levels.bass)
            }
            guard !intro else { return }

            if let stabSound {
                for s in stabSteps {
                    for note in chord { add(stabSound, note + 12, steps: 0.8, at: s, gain: levels.stabs / Float(chord.count), pan: 0.15) }
                }
            }
            // The second half of the loop adds a running arpeggio, so it doesn't feel stuck.
            if let arpSound, bar >= 8 {
                var tone = 0
                for s in stride(from: 0, to: 16, by: arpStep) {
                    let note = chord[tone % chord.count] + 12 + (tone / chord.count % 2) * 12
                    add(arpSound, note, steps: Double(arpStep) * 0.8, at: s, gain: levels.arp, pan: tone % 2 == 0 ? -0.35 : 0.35)
                    tone += 1
                }
            }
            for s in kick { add(.kick, 0, steps: 0, at: s, gain: levels.drums) }
            for s in snare { add(.snare, 0, steps: 0, at: s, gain: levels.drums * 0.55, pan: -0.05) }
            for s in clap { add(.clap, 0, steps: 0, at: s, gain: levels.drums * 0.6, pan: 0.05) }
            for s in hat { add(.hat, 0, steps: 0, at: s, gain: levels.drums * 0.22 * (s % 4 == 2 ? 1 : 0.7), pan: 0.3) }
            for s in shaker { add(.shaker, 0, steps: 0, at: s, gain: levels.drums * 0.12 * (s % 2 == 0 ? 1 : 0.6), pan: 0.35) }
            if boomEvery > 0, bar % boomEvery == 0 { add(.boom, 0, steps: 0, at: 0, gain: levels.drums * 0.9) }
            // A busier second half for the drum-led moods.
            if bar >= 8, mood == .dramatic {
                for s in stride(from: 0, to: 16, by: 2) { add(.hat, 0, steps: 0, at: s, gain: levels.drums * 0.12, pan: 0.3) }
            }
        }
    }
}
